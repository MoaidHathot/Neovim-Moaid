#!/usr/bin/env -S dotnet --
// Run with: dotnet run --file TajAgents.cs --no-launch-profile --verbosity quiet
// OverShell supplies versioned JSON-line snapshots on stdin; stdout is its command channel.
#:property TargetFramework=net11.0-windows
#:property Nullable=enable
#:property ImplicitUsings=enable

using System.Globalization;
using System.IO.Pipes;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;

public static class TajAgents
{
    public static async Task<int> Main()
    {
        Console.InputEncoding = new UTF8Encoding(false);
        Console.OutputEncoding = new UTF8Encoding(false);
        try
        {
            await new TajAgentBridge(Console.In, Console.Out, Console.Error).RunAsync();
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"Taj agents: {exception.Message}");
            return 1;
        }
    }
}

public sealed record TajAgentOptions(JsonObject Settings)
{
    public const int Slots = 12; // Match the twelve optional slots in shubbak.kdl.
    public bool ShowIdle => Flag(Settings, "showIdle");
    public bool ShowExited => Flag(Settings, "showExited");
    public bool ShowUnknown => Flag(Settings, "showUnknown", true);
    public bool ShowCount => Flag(Settings, "showCount", true);
    public bool DeduplicateSessions => Flag(Settings, "deduplicateSessions", true);
    public int MaxAgents => Math.Clamp(Number(Settings, "maxAgents", Slots), 1, Slots);
    public int LabelLength => Math.Clamp(Number(Settings, "labelLength", 10), 1, 40);
    public string Label => Text(Settings, "label") ?? "harness";
    public string Prefix => Text(Settings, "signalPrefix") ?? "overshell";
    public string ControlSignal => Text(Settings, "controlSignal") ?? "overshell-agents";
    public string OnlineContext => Text(Settings, "onlineContext") ?? "overshell-agents-online";
    public string PipeName { get; } = Text(Settings, "pipeName") ?? DefaultPipeName;

    private static string DefaultPipeName
    {
        get
        {
            using var identity = WindowsIdentity.GetCurrent();
            var instance = Environment.GetEnvironmentVariable("SHUBBAK_INSTANCE");
            return $"shubbak-v2-{identity.User!.Value}" + (string.IsNullOrEmpty(instance) ? "" : "-" + instance);
        }
    }

    public string HarnessLabel(string harness) => Text(Settings["harnessLabels"], harness) ?? harness.ToLowerInvariant() switch
    {
        "opencode" => "OC", "copilot" => "GH", "claude" => "CL", "codex" => "CX", _ => "AI",
    };

    public string StateGlyph(string state) => Text(Settings["stateGlyphs"], state) ?? state switch
    {
        "working" => "●", "blocked" => "?", "error" => "!", "done" => "✓",
        "idle" => "○", "exited" => "×", _ => "…",
    };

    public static string? Text(JsonNode? node, string key) =>
        node is JsonObject obj && obj[key] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;
    public static bool Flag(JsonNode? node, string key, bool fallback = false) =>
        node is JsonObject obj && obj[key] is JsonValue value && value.TryGetValue<bool>(out var flag) ? flag : fallback;
    public static int Number(JsonNode? node, string key, int fallback) =>
        node is JsonObject obj && obj[key] is JsonValue value && value.TryGetValue<int>(out var number) ? number : fallback;
}

public sealed record TajAgent(string Key, string TabId, string Harness, string State, string Label, string Project);
public sealed record TajAgentView(TajAgentOptions Options, IReadOnlyDictionary<string, string> Values,
    IReadOnlyDictionary<int, string> Targets, string? AttentionTarget, string? OverflowTarget);

/// <summary>Session identity and visibility belong here, in the dotfiles, rather than in either application.</summary>
public sealed class TajAgentModel
{
    private readonly Dictionary<string, int> _numbers = new(StringComparer.Ordinal);
    private readonly string?[] _slots = new string?[TajAgentOptions.Slots];

    public TajAgentView Render(JsonObject snapshot)
    {
        var options = new TajAgentOptions(snapshot["settings"] as JsonObject ?? new());
        var agents = (snapshot["tabs"] as JsonArray ?? []).OfType<JsonObject>()
            .Where(tab => TajAgentOptions.Flag(tab, "isAgent"))
            .Select(tab => ReadAgent(tab, options))
            .GroupBy(agent => agent.Key, StringComparer.Ordinal)
            .Select(group => group.OrderBy(agent => Priority(agent.State)).First()).ToArray();
        var liveKeys = agents.Select(agent => agent.Key).ToHashSet(StringComparer.Ordinal);
        foreach (var key in _numbers.Keys.Where(key => !liveKeys.Contains(key)).ToArray()) _numbers.Remove(key);
        foreach (var agent in agents)
        {
            if (_numbers.ContainsKey(agent.Key)) continue;
            var number = 1;
            while (_numbers.ContainsValue(number)) number++;
            _numbers[agent.Key] = number;
        }

        var visible = agents.Where(agent => agent.State switch
        {
            "idle" => options.ShowIdle,
            "exited" => options.ShowExited,
            "unknown" => options.ShowUnknown,
            _ => true,
        }).OrderBy(agent => Priority(agent.State)).ThenBy(agent => _numbers[agent.Key]).ToArray();
        var selected = visible.Take(options.MaxAgents).ToDictionary(agent => agent.Key, StringComparer.Ordinal);
        // Retain a session's slot across state changes. A newly blocked session can take
        // an overflow slot, but existing visible sessions do not shuffle on every update.
        for (var i = 0; i < _slots.Length; i++)
            if (_slots[i] is { } key && (!selected.ContainsKey(key) || i >= options.MaxAgents)) _slots[i] = null;
        foreach (var agent in selected.Values)
        {
            if (_slots.Contains(agent.Key)) continue;
            _slots[Array.IndexOf(_slots, null)] = agent.Key;
        }

        var values = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [options.Prefix + ".count"] = options.ShowCount && visible.Length > 0 ? $"AI {visible.Length}" : "",
            [options.Prefix + ".overflow"] = visible.Length > selected.Count ? $"+{visible.Length - selected.Count}" : "",
        };
        var targets = new Dictionary<int, string>();
        for (var i = 0; i < _slots.Length; i++)
        {
            var source = $"{options.Prefix}.agent.{i + 1}";
            if (_slots[i] is not { } key)
            {
                values[source] = values[source + ".state"] = "";
                continue;
            }
            var agent = selected[key];
            var name = options.Label switch { "project" => agent.Project, "session" => agent.Label, _ => "" };
            name = string.Concat(name.EnumerateRunes().Take(options.LabelLength).Select(rune => rune.ToString()));
            values[source] = $"{options.HarnessLabel(agent.Harness)}{_numbers[key]}{options.StateGlyph(agent.State)}" + (name.Length > 0 ? " " + name : "");
            values[source + ".state"] = agent.State;
            targets[i + 1] = agent.TabId;
        }
        return new(options, values, targets, visible.FirstOrDefault()?.TabId, visible.Skip(selected.Count).FirstOrDefault()?.TabId);
    }

    private static TajAgent ReadAgent(JsonObject tab, TajAgentOptions options)
    {
        var id = TajAgentOptions.Text(tab, "id") ?? throw new JsonException("A tab has no id");
        var harness = TajAgentOptions.Text(tab, "harness") ?? "generic";
        var session = TajAgentOptions.Text(tab, "sessionId");
        var key = harness + "\0" + (options.DeduplicateSessions && !string.IsNullOrEmpty(session) ? "session:" + session : "tab:" + id);
        var state = (TajAgentOptions.Text(tab, "state") ?? "unknown").ToLowerInvariant();
        if (!TajAgentOptions.Flag(tab, "isRunning", true) || state == "exited") state = "exited";
        else if (tab["request"] is JsonObject || state == "blocked") state = "blocked";
        else if (state is "idle" or "done")
            state = TajAgentOptions.Flag(tab, "unread") || TajAgentOptions.Flag(tab, "needsAttention") ? "done" : "idle";
        if (state is not ("working" or "blocked" or "error" or "done" or "idle" or "exited")) state = "unknown";
        return new(key, id, harness, state,
            TajAgentOptions.Text(tab, "sessionTitle") ?? TajAgentOptions.Text(tab, "label") ?? "",
            TajAgentOptions.Text(tab, "project") ?? "");
    }

    private static int Priority(string state) => state switch
    {
        "blocked" => 0, "error" => 1, "done" => 2, "working" => 3, "unknown" => 4, "idle" => 5, _ => 6,
    };
}

/// <summary>One stdin feed and one persistent named pipe; nothing polls while connected.</summary>
public sealed class TajAgentBridge(TextReader input, TextWriter output, TextWriter log)
{
    private readonly Channel<bool> _wake = Channel.CreateBounded<bool>(new BoundedChannelOptions(1) { FullMode = BoundedChannelFullMode.DropOldest });
    private readonly Channel<string> _clicks = Channel.CreateBounded<string>(new BoundedChannelOptions(16) { FullMode = BoundedChannelFullMode.DropOldest });
    private readonly TajAgentModel _model = new();
    private volatile JsonObject? _snapshot;
    private volatile TajAgentView? _published;
    private int _force;

    public async Task RunAsync(CancellationToken cancellation = default)
    {
        using var stop = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        // Console.In is a synchronized TextReader: even ReadLineAsync may block its
        // caller. Keep that wait off the publisher's loop.
        var reading = Task.Run(() => ReadInputAsync(stop.Token));
        var publishing = PublishLoopAsync(stop.Token);
        try
        {
            var completed = await Task.WhenAny(reading, publishing);
            await completed;
        }
        catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
        finally
        {
            stop.Cancel();
            try { await publishing; }
            catch (OperationCanceledException) { }
        }
    }

    private async Task ReadInputAsync(CancellationToken cancellation)
    {
        while (await input.ReadLineAsync(cancellation) is { } line)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                if (JsonNode.Parse(line) is not JsonObject message) continue;
                var type = TajAgentOptions.Text(message, "type");
                if (type == "shutdown") return;
                if (type != "snapshot" || TajAgentOptions.Number(message, "protocol", 0) != 1) continue;
                _snapshot = message;
                _wake.Writer.TryWrite(true);
            }
            catch (JsonException exception) { await log.WriteLineAsync($"Invalid host snapshot: {exception.Message}"); }
        }
    }

    private async Task PublishLoopAsync(CancellationToken cancellation)
    {
        var retry = 1000;
        while (!cancellation.IsCancellationRequested)
        {
            if (_snapshot is null)
            {
                await _wake.Reader.ReadAsync(cancellation);
                continue;
            }
            var view = _model.Render(_snapshot);
            await using var connection = new TajPipe(view.Options.PipeName, OnEvent);
            var sent = new Dictionary<string, string>(StringComparer.Ordinal);
            try
            {
                await connection.ConnectAsync(cancellation);
                await connection.SendAsync("subscribe", "signal,config.reloaded,wm.resync", cancellation);
                Interlocked.Exchange(ref _force, 1);
                _wake.Writer.TryWrite(true);
                while (!cancellation.IsCancellationRequested)
                {
                    // Await either changes or a lost pipe. There is no refresh timer.
                    using var wait = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
                    var changed = _wake.Reader.WaitToReadAsync(wait.Token).AsTask();
                    var completed = await Task.WhenAny(changed, connection.Completion);
                    wait.Cancel();
                    if (completed == connection.Completion) { await connection.Completion; throw new IOException("Shubbak disconnected"); }
                    cancellation.ThrowIfCancellationRequested();
                    while (_wake.Reader.TryRead(out _)) { }
                    // Clicks capture the last published target, not a later session in
                    // a slot that has since been reused.
                    while (_clicks.Reader.TryRead(out var tab))
                    {
                        await output.WriteLineAsync(new JsonObject
                        {
                            ["type"] = "command", ["command"] = "tab.activate",
                            ["arguments"] = new JsonObject { ["target"] = new JsonObject { ["id"] = tab } },
                        }.ToJsonString());
                        await output.FlushAsync(cancellation);
                    }
                    var next = _model.Render(_snapshot!);
                    if (next.Options.PipeName != view.Options.PipeName || next.Options.Prefix != view.Options.Prefix ||
                        next.Options.OnlineContext != view.Options.OnlineContext) break;
                    view = next;
                    var force = Interlocked.Exchange(ref _force, 0) != 0;
                    foreach (var (name, value) in view.Values)
                    {
                        if (!force && sent.GetValueOrDefault(name) == value) continue;
                        await connection.SignalAsync(name, value, cancellation);
                        sent[name] = value;
                    }
                    // The profile is visible only while this pipe owns the lease. A
                    // killed publisher or OverShell crash therefore hides stale signals.
                    if (force) await connection.SendAsync("command", $"context --set {TajPipe.Quote(view.Options.OnlineContext)} --lease", cancellation);
                    _published = view;
                    retry = 1000;
                }
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
            catch (Exception exception) when (exception is IOException or TimeoutException or InvalidOperationException or UnauthorizedAccessException or JsonException)
            {
                await log.WriteLineAsync($"Taj IPC: {exception.Message}; retry in {retry / 1000}s");
            }
            finally
            {
                _published = null;
                using var cleanup = new CancellationTokenSource(700);
                try
                {
                    if (connection.Connected)
                    {
                        foreach (var name in sent.Keys) await connection.SignalAsync(name, "", cleanup.Token);
                    }
                }
                catch (Exception exception) when (exception is IOException or OperationCanceledException or TimeoutException or InvalidOperationException) { }
                // Disposing closes the connection and releases its context even if
                // the server could not acknowledge the final clears.
            }
            if (cancellation.IsCancellationRequested) return;
            await connection.DisposeAsync();
            await Task.Delay(retry, cancellation);
            retry = Math.Min(30_000, retry * 2);
        }
    }

    private void OnEvent(string topic, JsonObject? data)
    {
        if (topic == "wm.resync" || topic == "config.reloaded" && TajAgentOptions.Flag(data, "accepted", true) ||
            topic == "signal" && TajAgentOptions.Text(data, "name") == "announce")
        {
            Interlocked.Exchange(ref _force, 1);
            _wake.Writer.TryWrite(true);
            return;
        }
        var view = _published;
        if (topic != "signal" || view is null || TajAgentOptions.Text(data, "name") != view.Options.ControlSignal || data?["arguments"] is not JsonArray arguments) return;
        var action = arguments.FirstOrDefault()?.GetValue<string>();
        string? target = null;
        if (action == "focus" && arguments.Count > 1 && int.TryParse(arguments[1]?.GetValue<string>(), CultureInfo.InvariantCulture, out var slot))
            target = view.Targets.GetValueOrDefault(slot);
        else if (action == "attention") target = view.AttentionTarget;
        else if (action == "overflow") target = view.OverflowTarget;
        if (target is not null)
        {
            _clicks.Writer.TryWrite(target);
            _wake.Writer.TryWrite(true);
        }
    }
}

/// <summary>The documented Shubbak v2 wire format, with one reader for replies and events.</summary>
public sealed class TajPipe(string name, Action<string, JsonObject?> onEvent) : IAsyncDisposable
{
    private readonly NamedPipeClientStream _pipe = new(".", name, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
    private readonly CancellationTokenSource _stop = new();
    private StreamReader? _reader;
    private StreamWriter? _writer;
    private volatile Pending? _pending;
    private int _id;
    private bool _disposed;
    private bool _broken;
    private sealed record Pending(int Id, TaskCompletionSource<JsonObject> Reply);
    public Task Completion { get; private set; } = Task.CompletedTask;
    public bool Connected => !_broken && _pipe.IsConnected && !Completion.IsCompleted;

    public async Task ConnectAsync(CancellationToken cancellation)
    {
        await _pipe.ConnectAsync(500, cancellation);
        _reader = new StreamReader(_pipe, Encoding.UTF8, leaveOpen: true);
        _writer = new StreamWriter(_pipe, new UTF8Encoding(false), leaveOpen: true) { NewLine = "\n" };
        Completion = ReadAsync(_stop.Token);
    }

    // Called serially by the publisher. Reading always continues while a reply is awaited.
    public async Task SendAsync(string method, string payload, CancellationToken cancellation)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(10));
        var pending = new Pending(++_id, new(TaskCreationOptions.RunContinuationsAsynchronously));
        _pending = pending;
        try
        {
            if (Completion.IsCompleted) { await Completion; throw new IOException("Pipe is closed"); }
            var request = new JsonObject { ["method"] = method, ["payload"] = payload, ["id"] = pending.Id }.ToJsonString();
            _broken = true;
            await _writer!.WriteLineAsync(request.AsMemory(), timeout.Token);
            await _writer.FlushAsync(timeout.Token);
            var response = await pending.Reply.Task.WaitAsync(timeout.Token);
            _broken = false;
            if (!TajAgentOptions.Flag(response, "ok")) throw new InvalidOperationException(TajAgentOptions.Text(response, "error") ?? "Request refused");
        }
        catch (OperationCanceledException) when (!cancellation.IsCancellationRequested)
        {
            throw new TimeoutException($"Shubbak did not answer {method} within 10 seconds");
        }
        finally
        {
            _pending = null;
            pending.Reply.TrySetCanceled();
            _ = pending.Reply.Task.Exception;
        }
    }

    public Task SignalAsync(string name, string value, CancellationToken cancellation) =>
        SendAsync("command", $"signal {Quote(name)}" + (value.Length == 0 ? "" : " " + Quote(value)), cancellation);

    // The command parser honours surrounding quotes but has no backslash escapes.
    // A typographic double quote keeps user labels displayable even with both quote kinds.
    public static string Quote(string text) => "\"" + text.Replace('"', '”').Replace('\r', ' ').Replace('\n', ' ') + "\"";

    private async Task ReadAsync(CancellationToken cancellation)
    {
        try
        {
            while (await _reader!.ReadLineAsync(cancellation) is { } line)
            {
                if (JsonNode.Parse(line) is not JsonObject message) continue;
                if (TajAgentOptions.Text(message, "topic") is { } topic)
                {
                    var data = TajAgentOptions.Text(message, "data");
                    onEvent(topic, data is null ? null : JsonNode.Parse(data) as JsonObject);
                }
                else if (_pending is { } pending && TajAgentOptions.Number(message, "id", -1) == pending.Id)
                    pending.Reply.TrySetResult(message);
            }
        }
        finally { _pending?.Reply.TrySetException(new IOException("Shubbak closed the pipe")); }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        _stop.Cancel();
        _pipe.Dispose();
        try { await Completion; }
        catch (Exception exception) when (exception is IOException or OperationCanceledException or ObjectDisposedException or JsonException or InvalidOperationException) { }
        _reader?.Dispose();
        try { _writer?.Dispose(); }
        catch (Exception exception) when (exception is IOException or ObjectDisposedException) { }
        _stop.Dispose();
    }
}
