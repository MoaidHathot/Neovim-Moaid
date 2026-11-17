#!/usr/bin/env -S dotnet --
// dotnet run --file TajAgents.Tests.cs --no-launch-profile --verbosity quiet
#:include TajAgents.cs
#:property StartupObject=TajAgentsTests

using System.Collections.Concurrent;
using System.IO.Pipes;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Threading.Channels;

public static class TajAgentsTests
{
    private static int _checks;
    public static async Task<int> Main()
    {
        try
        {
            VisibilityAndIdentity();
            OverflowAndStableSlots();
            await PipeLifecycleAsync();
            Console.WriteLine($"PASS: {_checks} checks (session visibility, identity, overflow, IPC replay, click, reconnect, shutdown)");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
    }

    private static void VisibilityAndIdentity()
    {
        var tabs = new JsonArray(
            Tab("shell", "Working", agent: false), Tab("idle", "Idle"), Tab("read", "Done"),
            Tab("unread", "Done", unread: true), Tab("question", "Idle", request: true),
            Tab("exited", "Exited"), Tab("failed", "Error"), Tab("working", "Working")
        );
        var snapshot = Snapshot(tabs);
        var model = new TajAgentModel();
        var view = model.Render(snapshot);
        Check(view.Values["overshell.count"] == "AI 4", "shells, read idle/done, and exits are excluded");
        Check(view.Targets.Values.ToHashSet().SetEquals(["unread", "question", "failed", "working"]), "every actionable session is retained");
        Check(view.Values.Values.Contains("blocked"), "an explicit pending request overrides an idle state");
        Check(view.Values.Values.Contains("done"), "an unread completion is visible");
        snapshot["settings"]!["showIdle"] = true;
        Check(model.Render(snapshot).Values["overshell.count"] == "AI 6", "showIdle includes reviewed results and idle sessions");
        snapshot["settings"]!["showExited"] = true;
        Check(model.Render(snapshot).Values["overshell.count"] == "AI 7", "exited sessions are independently configurable");

        var first = Tab("one", "Working", session: "shared");
        var second = Tab("two", "Blocked", session: "shared");
        var deduplicated = Snapshot(new JsonArray(first, second));
        view = new TajAgentModel().Render(deduplicated);
        Check(view.Values["overshell.count"] == "AI 1" && view.Targets.Values.Single() == "two", "two views of a session count once and the waiting view wins");
        deduplicated["settings"]!["deduplicateSessions"] = false;
        Check(new TajAgentModel().Render(deduplicated).Values["overshell.count"] == "AI 2", "deduplication can be disabled");
        first["sessionId"] = null;
        second["sessionId"] = null;
        deduplicated["settings"]!["deduplicateSessions"] = true;
        Check(new TajAgentModel().Render(deduplicated).Values["overshell.count"] == "AI 2", "unknown session identities are not falsely merged");

        var result = Tab("result", "Done", unread: true);
        var review = Snapshot(new JsonArray(result));
        Check(new TajAgentModel().Render(review).Targets.Count == 1, "unread result is initially present");
        result["unread"] = false;
        Check(new TajAgentModel().Render(review).Targets.Count == 0, "acknowledging the result hides it without needing a state change");
        Check(TajPipe.Quote("a\"b'c\\d\ne") == "\"a”b'c\\d e\"", "signal quoting matches Shubbak's non-backslash command language");
    }

    private static void OverflowAndStableSlots()
    {
        var work = Tab("work", "Working");
        var second = Tab("second", "Working");
        var snapshot = Snapshot(new JsonArray(work, second));
        var model = new TajAgentModel();
        var before = model.Render(snapshot);
        second["state"] = "Blocked";
        var after = model.Render(snapshot);
        Check(before.Targets.OrderBy(pair => pair.Key).SequenceEqual(after.Targets.OrderBy(pair => pair.Key)), "state changes keep existing session slots stable");
        snapshot["settings"]!["maxAgents"] = 1;
        var limited = model.Render(snapshot);
        Check(limited.Targets.Values.Single() == "second", "waiting session takes priority under a size limit");
        Check(limited.Values["overshell.overflow"] == "+1" && limited.OverflowTarget == "work", "overflow is counted and reachable");
        Check(limited.Values["overshell.agent.2"] == "", "shrinking clears vacated slots");
        snapshot["settings"]!["showCount"] = false;
        Check(model.Render(snapshot).Values["overshell.count"] == "", "count can be hidden separately");

        var many = Snapshot(new JsonArray(Enumerable.Range(0, 15).Select(i => (JsonNode)Tab("t" + i, "Working")).ToArray()));
        many["settings"]!["maxAgents"] = 100;
        var capped = new TajAgentModel().Render(many);
        Check(capped.Targets.Count == 12 && capped.Values["overshell.overflow"] == "+3", "maximum slots remain bounded and excess agents stay counted");
    }

    private static async Task PipeLifecycleAsync()
    {
        var pipeName = "overshell-taj-test-" + Guid.NewGuid().ToString("N");
        var input = new InputLines();
        var output = new OutputLines();
        var errors = new StringWriter();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        await using var first = new FakeShubbak(pipeName);
        var snapshot = Snapshot(new JsonArray(Tab("live", "Working"), Tab("quiet", "Idle")));
        snapshot["settings"]!["pipeName"] = pipeName;
        var bridge = new TajAgentBridge(input, output, errors);
        var running = bridge.RunAsync(timeout.Token);
        input.Send(snapshot);
        await Until(() => first.Pinned && first.Values.GetValueOrDefault("overshell.count") == "AI 1", timeout.Token);
        Check(!first.PinnedBeforeSnapshot, "publishes a full snapshot before making the profile visible");
        var writes = first.SignalWrites;
        input.Send(snapshot);
        await Task.Delay(200, timeout.Token);
        Check(first.SignalWrites == writes, "unchanged snapshots cause no IPC writes");

        await first.EventAsync("signal", new JsonObject { ["name"] = "announce", ["arguments"] = new JsonArray() }, timeout.Token);
        await Until(() => first.SignalWrites >= writes + 26, timeout.Token);
        Check(first.Values["overshell.agent.1"].Contains("OC1●"), "Taj announce replays all sources, including Unicode");
        await first.EventAsync("signal", new JsonObject { ["name"] = "overshell-agents", ["arguments"] = new JsonArray("focus", "1") }, timeout.Token);
        var click = JsonNode.Parse(await output.ReadAsync(timeout.Token))!;
        Check(click["command"]!.GetValue<string>() == "tab.activate" && click["arguments"]!["target"]!["id"]!.GetValue<string>() == "live", "a bar click addresses the published agent's terminal");

        snapshot["tabs"]![0]!["state"] = "Done";
        snapshot["tabs"]![0]!["unread"] = true;
        input.Send(snapshot);
        await Until(() => first.Values.GetValueOrDefault("overshell.agent.1.state") == "done", timeout.Token);
        snapshot["tabs"]![0]!["unread"] = false;
        input.Send(snapshot);
        await Until(() => first.Values.GetValueOrDefault("overshell.count") == "", timeout.Token);
        Check(first.Values["overshell.agent.1"] == "", "reviewed results clear their actual bar sources");

        snapshot["settings"]!["showIdle"] = true;
        input.Send(snapshot);
        await Until(() => first.Values.GetValueOrDefault("overshell.count") == "AI 2", timeout.Token);
        await first.DisposeAsync();
        await using var second = new FakeShubbak(pipeName);
        await Until(() => second.Pinned && second.Values.GetValueOrDefault("overshell.count") == "AI 2", timeout.Token);
        Check(second.SignalWrites == 26, "Shubbak restart reconnects and restores the current state without polling OverShell");
        input.Complete();
        await running.WaitAsync(timeout.Token);
        await Until(() => second.Disconnected, timeout.Token);
        Check(!second.Pinned && second.Values.Values.All(value => value == ""), "EOF clears published values and closes the leased connection");
    }

    private static JsonObject Tab(string id, string state, bool agent = true, bool unread = false, bool request = false, string? session = null) => new()
    {
        ["id"] = id, ["isAgent"] = agent, ["harness"] = "opencode", ["state"] = state,
        ["unread"] = unread, ["isRunning"] = state != "Exited", ["sessionId"] = session ?? id,
        ["request"] = request ? new JsonObject { ["kind"] = "question" } : null,
    };

    private static JsonObject Snapshot(JsonArray tabs) => new()
    {
        ["type"] = "snapshot", ["protocol"] = 1, ["settings"] = new JsonObject(), ["tabs"] = tabs,
    };

    private static async Task Until(Func<bool> condition, CancellationToken cancellation)
    {
        while (!condition()) await Task.Delay(20, cancellation);
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("FAIL: " + message);
        _checks++;
    }

    private sealed class InputLines : TextReader
    {
        private readonly Channel<string> _lines = Channel.CreateUnbounded<string>();
        public void Send(JsonObject message) => _lines.Writer.TryWrite(message.ToJsonString());
        public void Complete() => _lines.Writer.TryComplete();
        public override async ValueTask<string?> ReadLineAsync(CancellationToken cancellation)
        {
            try { return await _lines.Reader.ReadAsync(cancellation); }
            catch (ChannelClosedException) { return null; }
        }
    }

    private sealed class OutputLines : TextWriter
    {
        private readonly Channel<string> _lines = Channel.CreateUnbounded<string>();
        public override Encoding Encoding => Encoding.UTF8;
        public override Task WriteLineAsync(string? value) { _lines.Writer.TryWrite(value ?? ""); return Task.CompletedTask; }
        public ValueTask<string> ReadAsync(CancellationToken cancellation) => _lines.Reader.ReadAsync(cancellation);
    }

    private sealed class FakeShubbak : IAsyncDisposable
    {
        private readonly NamedPipeServerStream _pipe;
        private readonly CancellationTokenSource _stop = new();
        private readonly SemaphoreSlim _writing = new(1, 1);
        private readonly Task _loop;
        private StreamWriter? _writer;
        private bool _disposed;
        public ConcurrentDictionary<string, string> Values { get; } = new();
        public int SignalWrites;
        public volatile bool Pinned;
        public volatile bool PinnedBeforeSnapshot;
        public volatile bool Disconnected;

        public FakeShubbak(string name)
        {
            _pipe = new(name, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            _loop = RunAsync();
        }

        private async Task RunAsync()
        {
            try
            {
                await _pipe.WaitForConnectionAsync(_stop.Token);
                using var reader = new StreamReader(_pipe, Encoding.UTF8, leaveOpen: true);
                _writer = new StreamWriter(_pipe, new UTF8Encoding(false), leaveOpen: true) { NewLine = "\n" };
                while (await reader.ReadLineAsync(_stop.Token) is { } line)
                {
                    var message = JsonNode.Parse(line)!;
                    var payload = message["payload"]!.GetValue<string>();
                    var signal = Regex.Match(payload, "^signal \"([^\"]+)\"(?: \"(.*)\")?$");
                    if (signal.Success)
                    {
                        Values[signal.Groups[1].Value] = signal.Groups[2].Value;
                        Interlocked.Increment(ref SignalWrites);
                    }
                    else if (payload.StartsWith("context --set"))
                    {
                        if (!Values.ContainsKey("overshell.count")) PinnedBeforeSnapshot = true;
                        Pinned = true;
                    }
                    // Send an event between request and reply to exercise multiplexing.
                    if (message["method"]!.GetValue<string>() == "subscribe")
                        await EventAsync("signal", new JsonObject { ["name"] = "irrelevant", ["arguments"] = new JsonArray("ignore") }, _stop.Token);
                    await WriteAsync(new JsonObject { ["id"] = message["id"]!.DeepClone(), ["ok"] = true }, _stop.Token);
                }
            }
            catch (Exception exception) when (exception is IOException or OperationCanceledException or ObjectDisposedException) { }
            finally { Pinned = false; Disconnected = true; }
        }

        public Task EventAsync(string topic, JsonObject data, CancellationToken cancellation) =>
            WriteAsync(new JsonObject { ["topic"] = topic, ["data"] = data.ToJsonString() }, cancellation);

        private async Task WriteAsync(JsonObject message, CancellationToken cancellation)
        {
            await _writing.WaitAsync(cancellation);
            try
            {
                await _writer!.WriteLineAsync(message.ToJsonString().AsMemory(), cancellation);
                await _writer.FlushAsync(cancellation);
            }
            finally { _writing.Release(); }
        }

        public async ValueTask DisposeAsync()
        {
            if (_disposed) return;
            _disposed = true;
            _stop.Cancel();
            _pipe.Dispose();
            await _loop;
            _stop.Dispose();
            _writing.Dispose();
        }
    }
}
