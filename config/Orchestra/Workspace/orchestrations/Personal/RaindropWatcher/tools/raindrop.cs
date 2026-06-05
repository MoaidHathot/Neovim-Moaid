#!/usr/bin/env dotnet
#:package System.Security.Cryptography.ProtectedData@8.0.0

// Raindrop.io CLI helper for the RaindropWatcher orchestration suite.
//
// Run with the .NET 10 file-based app launcher:
//   dotnet run raindrop.cs -- <command> [args]
//
// Authentication resolution order (per invocation):
//   1. $RAINDROP_TOKEN -- treat as a long-lived test/personal token.
//   2. $RAINDROP_OAUTH_CLIENT_ID + $RAINDROP_OAUTH_CLIENT_SECRET + persisted refresh token
//      at {state-dir}/raindrop-tokens.bin -- refresh + use OAuth access token.
//      If no token file exists on disk yet, the CLI automatically launches
//      the interactive OAuth login flow (browser pops up, user grants once).
//      Disable this with RAINDROP_AUTO_LOGIN=0.
//   3. Otherwise exit non-zero asking the user to set RAINDROP_TOKEN or
//      configure RAINDROP_OAUTH_CLIENT_ID/SECRET.
//
// Token file storage:
//   - Stored at {state-dir}/raindrop-tokens.bin.
//   - On Windows, the file is encrypted with DPAPI (CurrentUser scope) so it is
//     readable only by the same Windows user on the same machine.
//   - On Unix the file is plaintext JSON with chmod 600.
//
// State directory resolution (intentionally NON-synced -- tokens stay per-machine):
//   1. $RAINDROP_STATE_DIR  (explicit override; useful for tests)
//   2. Windows:    %LOCALAPPDATA%\Orchestra\RaindropWatcher
//   3. Unix:       $XDG_DATA_HOME/orchestra/raindrop-watcher
//   4. Unix:       $HOME/.local/share/orchestra/raindrop-watcher
//
// Legacy migration: if no token file exists at the new path but a plaintext
// {old-XDG_CONFIG_HOME}/orchestra/raindrop-tokens.json exists, it's read,
// re-encrypted at the new location, and the plaintext file is deleted.
//
// All success output is JSON on stdout. Human-readable diagnostics go to stderr.

using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

return await Cli.RunAsync(args);

static class Cli
{
    public static async Task<int> RunAsync(string[] args)
    {
        if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
        {
            PrintHelp();
            return args.Length == 0 ? 1 : 0;
        }

        var command = args[0];
        var rest = args.Skip(1).ToArray();

        try
        {
            return command switch
            {
                "login" => await Commands.LoginAsync(rest),
                "logout" => Commands.Logout(rest),
                "whoami" => await Commands.WhoAmIAsync(rest),
                "list-collections" => await Commands.ListCollectionsAsync(rest),
                "ensure-collection" => await Commands.EnsureCollectionAsync(rest),
                "list" => await Commands.ListAsync(rest),
                "get" => await Commands.GetAsync(rest),
                "move" => await Commands.MoveAsync(rest),
                "add-tag" => await Commands.MutateTagAsync(rest, add: true),
                "remove-tag" => await Commands.MutateTagAsync(rest, add: false),
                "tokens-show" => Commands.TokensShow(rest),
                _ => Fail($"unknown command: {command}. Run with --help."),
            };
        }
        catch (RaindropCliException ex)
        {
            Console.Error.WriteLine($"raindrop: {ex.Message}");
            return ex.ExitCode;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"raindrop: unexpected error: {ex.Message}");
            Console.Error.WriteLine(ex);
            return 99;
        }
    }

    static void PrintHelp()
    {
        Console.WriteLine("""
            raindrop -- raindrop.io helper for the RaindropWatcher orchestration

            Usage:
              raindrop login [--client-id <id>] [--client-secret <secret>] [--port <port>]
              raindrop logout
              raindrop whoami
              raindrop list-collections
              raindrop ensure-collection <title> [--parent <id>]
              raindrop list --collection <id> [--page-size <n>] [--max <n>] [--since <iso>]
              raindrop get <raindropId>
              raindrop move <raindropId> --to-collection <id> [--add-tag <t>]...
              raindrop add-tag <raindropId> <tag>
              raindrop remove-tag <raindropId> <tag>
              raindrop tokens-show

            Auth (resolved per call):
              1. RAINDROP_TOKEN env var (personal/test token).
              2. RAINDROP_OAUTH_CLIENT_ID + RAINDROP_OAUTH_CLIENT_SECRET
                 + persisted refresh token. The first call with no token
                 on disk auto-launches the interactive OAuth login flow.
                 Set RAINDROP_AUTO_LOGIN=0 to require an explicit
                 `raindrop login` instead.
              3. Otherwise fails with a remediation message.

            Output: JSON on stdout on success. Errors and progress on stderr.
            """);
    }

    static int Fail(string msg)
    {
        Console.Error.WriteLine($"raindrop: {msg}");
        return 2;
    }
}

// -------------------------------------------------------------------- Commands

static class Commands
{
    public static async Task<int> LoginAsync(string[] args)
    {
        var clientId = ArgParse.Get(args, "--client-id") ?? Env("RAINDROP_OAUTH_CLIENT_ID");
        var clientSecret = ArgParse.Get(args, "--client-secret") ?? Env("RAINDROP_OAUTH_CLIENT_SECRET");
        var portStr = ArgParse.Get(args, "--port") ?? "53682";
        if (!int.TryParse(portStr, out var port)) throw new RaindropCliException("--port must be an integer");

        if (string.IsNullOrWhiteSpace(clientId) || string.IsNullOrWhiteSpace(clientSecret))
            throw new RaindropCliException(
                "OAuth client id/secret required. Pass --client-id/--client-secret or set " +
                "RAINDROP_OAUTH_CLIENT_ID/RAINDROP_OAUTH_CLIENT_SECRET. Register an app at " +
                "https://app.raindrop.io/settings/integrations.");

        var auth = new OAuthFlow(clientId!, clientSecret!, port);
        var tokens = await auth.RunInteractiveAsync();
        TokenStore.Save(tokens);
        Console.Error.WriteLine($"raindrop: tokens saved to {TokenStore.Path}");
        Json.WriteToStdout(new JsonObject
        {
            ["ok"] = true,
            ["tokenStorePath"] = TokenStore.Path,
            ["expiresAt"] = tokens.ExpiresAt?.ToString("o"),
        });
        return 0;
    }

    public static int Logout(string[] args)
    {
        if (File.Exists(TokenStore.Path)) File.Delete(TokenStore.Path);
        Json.WriteToStdout(new JsonObject { ["ok"] = true, ["removed"] = TokenStore.Path });
        return 0;
    }

    public static async Task<int> WhoAmIAsync(string[] args)
    {
        var client = await RaindropClient.CreateAsync();
        var node = await client.GetJsonAsync("/user");
        Json.WriteToStdout(node);
        return 0;
    }

    public static async Task<int> ListCollectionsAsync(string[] args)
    {
        var client = await RaindropClient.CreateAsync();
        var rootCollections = await client.GetJsonAsync("/collections");
        var childCollections = await client.GetJsonAsync("/collections/childrens");
        var combined = new JsonObject
        {
            ["root"] = rootCollections?["items"]?.DeepClone(),
            ["children"] = childCollections?["items"]?.DeepClone(),
        };
        Json.WriteToStdout(combined);
        return 0;
    }

    public static async Task<int> EnsureCollectionAsync(string[] args)
    {
        if (args.Length < 1 || args[0].StartsWith("--"))
            throw new RaindropCliException("ensure-collection <title> [--parent <id>]");

        var title = args[0];
        var parentIdStr = ArgParse.Get(args, "--parent");
        long? parentId = null;
        if (parentIdStr is not null)
        {
            if (!long.TryParse(parentIdStr, out var pid))
                throw new RaindropCliException("--parent must be an integer collection id");
            parentId = pid;
        }

        var client = await RaindropClient.CreateAsync();

        // Look in both root collections and children for an exact title match.
        var existing = await FindCollectionByTitleAsync(client, title, parentId);
        if (existing is not null)
        {
            Json.WriteToStdout(new JsonObject
            {
                ["ok"] = true,
                ["created"] = false,
                ["id"] = existing.Value.Id,
                ["title"] = existing.Value.Title,
                ["parentId"] = existing.Value.ParentId,
            });
            return 0;
        }

        var payload = new JsonObject { ["title"] = title };
        if (parentId is not null)
            payload["parent"] = new JsonObject { ["$id"] = parentId.Value };

        var response = await client.PostJsonAsync("/collection", payload);
        var item = response?["item"];
        if (item is null) throw new RaindropCliException("create collection: empty response");
        var createdId = JsonNum.AsLong(item["_id"]) ?? throw new RaindropCliException("missing _id");
        Json.WriteToStdout(new JsonObject
        {
            ["ok"] = true,
            ["created"] = true,
            ["id"] = createdId,
            ["title"] = title,
            ["parentId"] = parentId,
        });
        return 0;
    }

    public static async Task<int> ListAsync(string[] args)
    {
        var collectionId = ArgParse.Require(args, "--collection", "list --collection <id>");
        if (!long.TryParse(collectionId, out var colId))
            throw new RaindropCliException("--collection must be an integer (use 0 for Unsorted, -1 for Trash)");

        var pageSize = int.Parse(ArgParse.Get(args, "--page-size") ?? "50");
        var max = int.Parse(ArgParse.Get(args, "--max") ?? "200");
        var sinceIso = ArgParse.Get(args, "--since");
        DateTimeOffset? since = null;
        if (!string.IsNullOrWhiteSpace(sinceIso))
        {
            if (!DateTimeOffset.TryParse(sinceIso, out var sinceParsed))
                throw new RaindropCliException("--since must be an ISO-8601 timestamp");
            since = sinceParsed;
        }

        var client = await RaindropClient.CreateAsync();
        var items = new JsonArray();
        var page = 0;
        var collected = 0;
        while (collected < max)
        {
            var url = $"/raindrops/{colId}?perpage={pageSize}&page={page}&sort=-created";
            var response = await client.GetJsonAsync(url);
            var pageItems = response?["items"]?.AsArray();
            if (pageItems is null || pageItems.Count == 0) break;

            var stop = false;
            foreach (var raw in pageItems)
            {
                if (raw is null) continue;
                if (since is not null && raw["created"] is JsonNode createdNode)
                {
                    if (DateTimeOffset.TryParse(createdNode.GetValue<string>(), out var createdAt))
                    {
                        if (createdAt < since.Value)
                        {
                            stop = true;
                            break;
                        }
                    }
                }
                items.Add(raw.DeepClone());
                collected++;
                if (collected >= max) { stop = true; break; }
            }
            if (stop || pageItems.Count < pageSize) break;
            page++;
        }

        Json.WriteToStdout(new JsonObject
        {
            ["ok"] = true,
            ["collectionId"] = colId,
            ["count"] = collected,
            ["items"] = items,
        });
        return 0;
    }

    public static async Task<int> GetAsync(string[] args)
    {
        if (args.Length < 1) throw new RaindropCliException("get <raindropId>");
        if (!long.TryParse(args[0], out var id)) throw new RaindropCliException("raindropId must be an integer");
        var client = await RaindropClient.CreateAsync();
        var response = await client.GetJsonAsync($"/raindrop/{id}");
        Json.WriteToStdout(response);
        return 0;
    }

    public static async Task<int> MoveAsync(string[] args)
    {
        if (args.Length < 1 || args[0].StartsWith("--"))
            throw new RaindropCliException("move <raindropId> --to-collection <id>");
        if (!long.TryParse(args[0], out var id)) throw new RaindropCliException("raindropId must be an integer");
        var targetStr = ArgParse.Require(args, "--to-collection", "--to-collection <id>");
        if (!long.TryParse(targetStr, out var target)) throw new RaindropCliException("--to-collection must be an integer");
        var extraTags = ArgParse.GetMany(args, "--add-tag");

        var client = await RaindropClient.CreateAsync();
        var current = await client.GetJsonAsync($"/raindrop/{id}");
        var currentTags = current?["item"]?["tags"]?.AsArray()?
            .Select(n => n?.GetValue<string>()).Where(s => !string.IsNullOrWhiteSpace(s))
            .ToList() ?? new List<string?>();
        foreach (var t in extraTags)
        {
            if (!currentTags.Contains(t, StringComparer.OrdinalIgnoreCase))
                currentTags.Add(t);
        }

        var body = new JsonObject
        {
            ["collection"] = new JsonObject { ["$id"] = target },
            ["tags"] = new JsonArray(currentTags.Select(t => (JsonNode)t!).ToArray()),
        };
        var response = await client.PutJsonAsync($"/raindrop/{id}", body);
        Json.WriteToStdout(response);
        return 0;
    }

    public static async Task<int> MutateTagAsync(string[] args, bool add)
    {
        if (args.Length < 2) throw new RaindropCliException($"{(add ? "add" : "remove")}-tag <raindropId> <tag>");
        if (!long.TryParse(args[0], out var id)) throw new RaindropCliException("raindropId must be an integer");
        var tag = args[1];

        var client = await RaindropClient.CreateAsync();
        var current = await client.GetJsonAsync($"/raindrop/{id}");
        var currentTags = current?["item"]?["tags"]?.AsArray()?
            .Select(n => n?.GetValue<string>()).Where(s => !string.IsNullOrWhiteSpace(s))
            .ToList() ?? new List<string?>();
        if (add)
        {
            if (!currentTags.Contains(tag, StringComparer.OrdinalIgnoreCase)) currentTags.Add(tag);
        }
        else
        {
            currentTags = currentTags.Where(t => !string.Equals(t, tag, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        var body = new JsonObject
        {
            ["tags"] = new JsonArray(currentTags.Select(t => (JsonNode)t!).ToArray()),
        };
        var response = await client.PutJsonAsync($"/raindrop/{id}", body);
        Json.WriteToStdout(response);
        return 0;
    }

    public static int TokensShow(string[] args)
    {
        // Always call Load() first -- it may migrate from a legacy plaintext
        // file on disk and create the new encrypted file as a side effect.
        var tokens = TokenStore.Load();
        if (tokens is null)
        {
            Json.WriteToStdout(new JsonObject
            {
                ["exists"] = false,
                ["path"] = TokenStore.Path,
                ["legacyPath"] = TokenStore.LegacyPath,
                ["legacyExists"] = File.Exists(TokenStore.LegacyPath),
                ["encrypted"] = OperatingSystem.IsWindows(),
            });
            return 0;
        }
        Json.WriteToStdout(new JsonObject
        {
            ["exists"] = true,
            ["path"] = TokenStore.Path,
            ["encrypted"] = OperatingSystem.IsWindows(),
            ["tokenType"] = tokens.TokenType,
            ["expiresAt"] = tokens.ExpiresAt?.ToString("o"),
            ["hasAccessToken"] = !string.IsNullOrEmpty(tokens.AccessToken),
            ["hasRefreshToken"] = !string.IsNullOrEmpty(tokens.RefreshToken),
        });
        return 0;
    }

    static async Task<CollectionMatch?> FindCollectionByTitleAsync(RaindropClient client, string title, long? parentId)
    {
        var root = await client.GetJsonAsync("/collections");
        foreach (var item in root?["items"]?.AsArray() ?? new JsonArray())
        {
            if (item is null) continue;
            if (string.Equals(item["title"]?.GetValue<string>(), title, StringComparison.OrdinalIgnoreCase) &&
                (parentId is null))
            {
                return new CollectionMatch(
                    JsonNum.AsLong(item["_id"]) ?? throw new RaindropCliException("collection missing _id"),
                    item["title"]!.GetValue<string>(),
                    null);
            }
        }
        var children = await client.GetJsonAsync("/collections/childrens");
        foreach (var item in children?["items"]?.AsArray() ?? new JsonArray())
        {
            if (item is null) continue;
            var parentObj = item["parent"];
            long? itemParent = JsonNum.AsLong(parentObj?["$id"]);
            if (string.Equals(item["title"]?.GetValue<string>(), title, StringComparison.OrdinalIgnoreCase) &&
                ((parentId is null) || itemParent == parentId))
            {
                return new CollectionMatch(
                    JsonNum.AsLong(item["_id"]) ?? throw new RaindropCliException("collection missing _id"),
                    item["title"]!.GetValue<string>(),
                    itemParent);
            }
        }
        return null;
    }

    readonly record struct CollectionMatch(long Id, string Title, long? ParentId);

    static string? Env(string name) => Environment.GetEnvironmentVariable(name);
}

// ---------------------------------------------------------------- HTTP Client

class RaindropClient
{
    static readonly string BaseUrl =
        Environment.GetEnvironmentVariable("RAINDROP_API_BASE")?.TrimEnd('/')
        ?? "https://api.raindrop.io/rest/v1";
    readonly HttpClient _http;
    readonly Func<Task<string>> _tokenProvider;
    readonly Func<Task<string>>? _refreshFn;

    RaindropClient(HttpClient http, Func<Task<string>> tokenProvider, Func<Task<string>>? refreshFn)
    {
        _http = http;
        _tokenProvider = tokenProvider;
        _refreshFn = refreshFn;
    }

    public static async Task<RaindropClient> CreateAsync()
    {
        var http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("RaindropWatcher/0.1 (+orchestra)");
        http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        var testToken = Environment.GetEnvironmentVariable("RAINDROP_TOKEN");
        if (!string.IsNullOrWhiteSpace(testToken))
        {
            return new RaindropClient(http, () => Task.FromResult(testToken!), null);
        }

        var clientId = Environment.GetEnvironmentVariable("RAINDROP_OAUTH_CLIENT_ID");
        var clientSecret = Environment.GetEnvironmentVariable("RAINDROP_OAUTH_CLIENT_SECRET");
        if (string.IsNullOrWhiteSpace(clientId) || string.IsNullOrWhiteSpace(clientSecret))
            throw new RaindropCliException(
                "no auth configured. Set RAINDROP_TOKEN (test token) or " +
                "RAINDROP_OAUTH_CLIENT_ID + RAINDROP_OAUTH_CLIENT_SECRET (login is automatic on first use).");

        // Trigger the interactive OAuth dance automatically if no token file is
        // on disk yet. Skipped only when the user opts out via RAINDROP_AUTO_LOGIN=0.
        // The Load() call also triggers the legacy plaintext migration if any.
        var existing = TokenStore.Load();
        if (existing is null)
        {
            var autoLoginRaw = Environment.GetEnvironmentVariable("RAINDROP_AUTO_LOGIN");
            var autoLoginDisabled =
                string.Equals(autoLoginRaw, "0", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(autoLoginRaw, "false", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(autoLoginRaw, "no", StringComparison.OrdinalIgnoreCase);

            if (autoLoginDisabled)
            {
                throw new RaindropCliException(
                    $"OAuth tokens not found at {TokenStore.Path} and RAINDROP_AUTO_LOGIN=0 disabled the auto flow. " +
                    "Run `raindrop login` once, or unset RAINDROP_AUTO_LOGIN.");
            }

            var portStr = Environment.GetEnvironmentVariable("RAINDROP_OAUTH_PORT");
            var port = int.TryParse(portStr, out var p) ? p : 53682;

            Console.Error.WriteLine("raindrop: no tokens found at " + TokenStore.Path);
            Console.Error.WriteLine("raindrop: starting one-time interactive OAuth login (set RAINDROP_AUTO_LOGIN=0 to disable)");
            var flow = new OAuthFlow(clientId!, clientSecret!, port);
            var fresh = await flow.RunInteractiveAsync();
            TokenStore.Save(fresh);
            Console.Error.WriteLine($"raindrop: tokens saved to {TokenStore.Path}");
        }

        async Task<string> GetTokenAsync()
        {
            var current = TokenStore.Load();
            if (current is null) throw new RaindropCliException("tokens disappeared");
            if (current.ExpiresAt is null || current.ExpiresAt > DateTimeOffset.UtcNow.AddMinutes(2))
                return current.AccessToken;

            var refreshed = await OAuthFlow.RefreshAsync(clientId!, clientSecret!, current.RefreshToken!);
            TokenStore.Save(refreshed);
            return refreshed.AccessToken;
        }

        return new RaindropClient(http, GetTokenAsync, GetTokenAsync);
    }

    public async Task<JsonNode?> GetJsonAsync(string path)
        => await SendAsync(HttpMethod.Get, path, body: null);

    public async Task<JsonNode?> PostJsonAsync(string path, JsonNode body)
        => await SendAsync(HttpMethod.Post, path, body);

    public async Task<JsonNode?> PutJsonAsync(string path, JsonNode body)
        => await SendAsync(HttpMethod.Put, path, body);

    async Task<JsonNode?> SendAsync(HttpMethod method, string path, JsonNode? body)
    {
        var attempt = 0;
        while (true)
        {
            attempt++;
            var token = await _tokenProvider();
            var req = new HttpRequestMessage(method, BaseUrl + path);
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            if (body is not null)
            {
                req.Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
            }
            using var res = await _http.SendAsync(req);
            if (res.StatusCode == HttpStatusCode.Unauthorized && _refreshFn is not null && attempt == 1)
            {
                // Force-refresh and retry once.
                Console.Error.WriteLine("raindrop: access token rejected, refreshing");
                await _refreshFn();
                continue;
            }
            if ((int)res.StatusCode == 429 && attempt <= 4)
            {
                var delay = TimeSpan.FromSeconds(Math.Pow(2, attempt));
                Console.Error.WriteLine($"raindrop: rate-limited, waiting {delay.TotalSeconds}s");
                await Task.Delay(delay);
                continue;
            }
            var text = await res.Content.ReadAsStringAsync();
            if (!res.IsSuccessStatusCode)
                throw new RaindropCliException(
                    $"raindrop {method} {path} failed: HTTP {(int)res.StatusCode} {res.ReasonPhrase}. Body: {Truncate(text, 1000)}",
                    exitCode: 4);
            return string.IsNullOrWhiteSpace(text) ? null : JsonNode.Parse(text);
        }
    }

    static string Truncate(string s, int max) => s.Length <= max ? s : s.Substring(0, max) + "...";
}

// -------------------------------------------------------------- OAuth

class OAuthFlow
{
    readonly string _clientId;
    readonly string _clientSecret;
    readonly int _port;

    public OAuthFlow(string clientId, string clientSecret, int port)
    {
        _clientId = clientId;
        _clientSecret = clientSecret;
        _port = port;
    }

    public async Task<RaindropTokens> RunInteractiveAsync()
    {
        var state = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
        var redirectUri = $"http://localhost:{_port}/raindrop-oauth-callback";
        var authorizeUrl =
            "https://raindrop.io/oauth/authorize" +
            $"?client_id={Uri.EscapeDataString(_clientId)}" +
            $"&redirect_uri={Uri.EscapeDataString(redirectUri)}" +
            $"&state={state}";

        Console.Error.WriteLine("raindrop: starting OAuth flow");
        Console.Error.WriteLine($"raindrop: listening on {redirectUri}");
        Console.Error.WriteLine($"raindrop: opening {authorizeUrl}");
        Console.Error.WriteLine($"raindrop: NOTE -- ensure this exact redirect URI is registered on your raindrop.io app");

        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://localhost:{_port}/");
        listener.Start();

        try
        {
            TryOpenBrowser(authorizeUrl);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"raindrop: could not auto-open browser ({ex.Message}). Open the URL above manually.");
        }

        var ctxTask = listener.GetContextAsync();
        var timeout = Task.Delay(TimeSpan.FromMinutes(5));
        var completed = await Task.WhenAny(ctxTask, timeout);
        if (completed == timeout)
        {
            throw new RaindropCliException("OAuth flow timed out after 5 minutes");
        }
        var ctx = await ctxTask;
        var query = ctx.Request.Url?.Query ?? string.Empty;
        var parsed = ParseQuery(query);
        var code = parsed.TryGetValue("code", out var c) ? c : null;
        var returnedState = parsed.TryGetValue("state", out var st) ? st : null;
        var error = parsed.TryGetValue("error", out var er) ? er : null;

        await RespondWithHtmlAsync(ctx.Response, error,
            error is null ? "You can close this window and return to the terminal." : $"OAuth failed: {error}");

        if (!string.IsNullOrEmpty(error))
            throw new RaindropCliException($"OAuth error from raindrop.io: {error}");
        if (string.IsNullOrEmpty(code))
            throw new RaindropCliException("OAuth callback missing code parameter");
        if (returnedState != state)
            throw new RaindropCliException("OAuth state mismatch -- aborting (possible CSRF)");

        return await ExchangeAsync(_clientId, _clientSecret, code!, redirectUri);
    }

    static async Task RespondWithHtmlAsync(HttpListenerResponse response, string? error, string message)
    {
        var status = string.IsNullOrEmpty(error) ? "success" : "error";
        var titleColor = error is null ? "#5fb85f" : "#e57373";
        var encodedMessage = WebUtility.HtmlEncode(message);
        var html = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Raindrop OAuth -- " + status + "</title>"
            + "<style>body{font-family:system-ui;background:#1a1a1a;color:#eee;padding:48px;text-align:center}"
            + "h1{color:" + titleColor + "}</style></head>"
            + "<body><h1>Raindrop OAuth: " + status + "</h1><p>" + encodedMessage + "</p></body></html>";
        var bytes = Encoding.UTF8.GetBytes(html);
        response.ContentType = "text/html; charset=utf-8";
        response.ContentLength64 = bytes.Length;
        await response.OutputStream.WriteAsync(bytes);
        response.OutputStream.Close();
    }

    public static async Task<RaindropTokens> ExchangeAsync(string clientId, string clientSecret, string code, string redirectUri)
    {
        using var http = new HttpClient();
        var req = new HttpRequestMessage(HttpMethod.Post, "https://raindrop.io/oauth/access_token");
        var bodyJson = new JsonObject
        {
            ["client_id"] = clientId,
            ["client_secret"] = clientSecret,
            ["code"] = code,
            ["grant_type"] = "authorization_code",
            ["redirect_uri"] = redirectUri,
        };
        req.Content = new StringContent(bodyJson.ToJsonString(), Encoding.UTF8, "application/json");
        using var res = await http.SendAsync(req);
        var text = await res.Content.ReadAsStringAsync();
        if (!res.IsSuccessStatusCode)
            throw new RaindropCliException($"OAuth token exchange failed: HTTP {(int)res.StatusCode} {res.ReasonPhrase}. Body: {text}");
        return ParseTokenResponse(text);
    }

    public static async Task<RaindropTokens> RefreshAsync(string clientId, string clientSecret, string refreshToken)
    {
        using var http = new HttpClient();
        var req = new HttpRequestMessage(HttpMethod.Post, "https://raindrop.io/oauth/access_token");
        var bodyJson = new JsonObject
        {
            ["client_id"] = clientId,
            ["client_secret"] = clientSecret,
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken,
        };
        req.Content = new StringContent(bodyJson.ToJsonString(), Encoding.UTF8, "application/json");
        using var res = await http.SendAsync(req);
        var text = await res.Content.ReadAsStringAsync();
        if (!res.IsSuccessStatusCode)
            throw new RaindropCliException($"OAuth token refresh failed: HTTP {(int)res.StatusCode} {res.ReasonPhrase}. Body: {text}");
        var refreshed = ParseTokenResponse(text);
        if (string.IsNullOrEmpty(refreshed.RefreshToken)) refreshed.RefreshToken = refreshToken;
        return refreshed;
    }

    static RaindropTokens ParseTokenResponse(string text)
    {
        var node = JsonNode.Parse(text) as JsonObject
            ?? throw new RaindropCliException("OAuth response was not a JSON object");
        var access = node["access_token"]?.GetValue<string>()
            ?? throw new RaindropCliException("OAuth response missing access_token");
        var refresh = node["refresh_token"]?.GetValue<string?>();
        var tokenType = node["token_type"]?.GetValue<string?>();
        var expiresIn = JsonNum.AsLong(node["expires_in"]);
        return new RaindropTokens
        {
            AccessToken = access,
            RefreshToken = refresh,
            TokenType = tokenType ?? "Bearer",
            ExpiresAt = expiresIn is null ? null : DateTimeOffset.UtcNow.AddSeconds(expiresIn.Value),
        };
    }

    static void TryOpenBrowser(string url)
    {
        if (OperatingSystem.IsWindows())
        {
            Process.Start(new ProcessStartInfo("cmd", $"/c start \"\" \"{url}\"") { CreateNoWindow = true });
        }
        else if (OperatingSystem.IsMacOS())
        {
            Process.Start("open", url);
        }
        else
        {
            Process.Start("xdg-open", url);
        }
    }

    static Dictionary<string, string> ParseQuery(string query)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrEmpty(query)) return result;
        if (query.StartsWith('?')) query = query.Substring(1);
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var idx = pair.IndexOf('=');
            string key, val;
            if (idx < 0)
            {
                key = WebUtility.UrlDecode(pair);
                val = string.Empty;
            }
            else
            {
                key = WebUtility.UrlDecode(pair.Substring(0, idx));
                val = WebUtility.UrlDecode(pair.Substring(idx + 1));
            }
            result[key] = val;
        }
        return result;
    }
}

// -------------------------------------------------------------- Token Storage

class RaindropTokens
{
    public string AccessToken { get; set; } = string.Empty;
    public string? RefreshToken { get; set; }
    public string? TokenType { get; set; }
    public DateTimeOffset? ExpiresAt { get; set; }
}

static class TokenStore
{
    public static readonly string Path = ResolvePath();
    public static readonly string LegacyPath = ResolveLegacyPath();

    static string ResolvePath()
    {
        var explicitDir = Environment.GetEnvironmentVariable("RAINDROP_STATE_DIR");
        if (!string.IsNullOrWhiteSpace(explicitDir))
            return System.IO.Path.Combine(explicitDir, "raindrop-tokens.bin");

        if (OperatingSystem.IsWindows())
        {
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return System.IO.Path.Combine(local, "Orchestra", "RaindropWatcher", "raindrop-tokens.bin");
        }

        var xdgData = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
        if (!string.IsNullOrWhiteSpace(xdgData))
            return System.IO.Path.Combine(xdgData, "orchestra", "raindrop-watcher", "raindrop-tokens.bin");

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return System.IO.Path.Combine(home, ".local", "share", "orchestra", "raindrop-watcher", "raindrop-tokens.bin");
    }

    // The old plaintext location used before the DPAPI/non-synced switch.
    // Migrate from here on first Load() if the new path is empty.
    static string ResolveLegacyPath()
    {
        var xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        if (!string.IsNullOrWhiteSpace(xdg))
            return System.IO.Path.Combine(xdg, "orchestra", "raindrop-tokens.json");

        if (OperatingSystem.IsWindows())
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            return System.IO.Path.Combine(appData, "orchestra", "raindrop-tokens.json");
        }

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return System.IO.Path.Combine(home, ".config", "orchestra", "raindrop-tokens.json");
    }

    public static RaindropTokens? Load()
    {
        if (!File.Exists(Path))
        {
            // Try the legacy plaintext file once; migrate-and-delete on success.
            if (File.Exists(LegacyPath))
            {
                try
                {
                    var legacyJson = File.ReadAllText(LegacyPath);
                    var legacyTokens = ParseJson(legacyJson);
                    if (legacyTokens is not null && !string.IsNullOrEmpty(legacyTokens.AccessToken))
                    {
                        Save(legacyTokens);
                        try { File.Delete(LegacyPath); } catch { /* best effort */ }
                        Console.Error.WriteLine(
                            $"raindrop: migrated tokens from legacy plaintext {LegacyPath} -> encrypted {Path}");
                        return legacyTokens;
                    }
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"raindrop: legacy token migration failed ({ex.Message}); ignoring");
                }
            }
            return null;
        }

        var bytes = File.ReadAllBytes(Path);
        string json;
        if (OperatingSystem.IsWindows())
        {
            try
            {
                var plaintext = ProtectedData.Unprotect(bytes, optionalEntropy: null, DataProtectionScope.CurrentUser);
                json = Encoding.UTF8.GetString(plaintext);
            }
            catch (CryptographicException ex)
            {
                throw new RaindropCliException(
                    $"failed to decrypt token file {Path}: {ex.Message}. " +
                    "This file is bound to the current Windows user on this machine; if you've " +
                    "copied it from another machine, delete it and re-run `raindrop login`.",
                    exitCode: 5);
            }
        }
        else
        {
            json = Encoding.UTF8.GetString(bytes);
        }

        return ParseJson(json);
    }

    public static void Save(RaindropTokens tokens)
    {
        var dir = System.IO.Path.GetDirectoryName(Path)!;
        Directory.CreateDirectory(dir);

        var node = new JsonObject
        {
            ["access_token"] = tokens.AccessToken,
            ["refresh_token"] = tokens.RefreshToken,
            ["token_type"] = tokens.TokenType,
            ["expires_at"] = tokens.ExpiresAt?.ToString("o"),
        };
        var json = node.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        var plaintext = Encoding.UTF8.GetBytes(json);

        if (OperatingSystem.IsWindows())
        {
            var encrypted = ProtectedData.Protect(plaintext, optionalEntropy: null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(Path, encrypted);
        }
        else
        {
            File.WriteAllBytes(Path, plaintext);
            try { File.SetUnixFileMode(Path, UnixFileMode.UserRead | UnixFileMode.UserWrite); }
            catch { /* best effort */ }
        }
    }

    static RaindropTokens? ParseJson(string json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        var node = JsonNode.Parse(json) as JsonObject;
        if (node is null) return null;
        return new RaindropTokens
        {
            AccessToken = node["access_token"]?.GetValue<string>() ?? string.Empty,
            RefreshToken = node["refresh_token"]?.GetValue<string?>(),
            TokenType = node["token_type"]?.GetValue<string?>(),
            ExpiresAt = node["expires_at"] is JsonNode ea && DateTimeOffset.TryParse(ea.GetValue<string>(), out var dt)
                ? dt
                : null,
        };
    }
}

// -------------------------------------------------------------- Utilities

static class ArgParse
{
    public static string? Get(string[] args, string key)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == key) return args[i + 1];
        }
        return null;
    }

    public static string Require(string[] args, string key, string usage)
    {
        var val = Get(args, key);
        if (val is null) throw new RaindropCliException($"missing required {key}. Usage: {usage}");
        return val;
    }

    public static List<string> GetMany(string[] args, string key)
    {
        var result = new List<string>();
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == key) result.Add(args[i + 1]);
        }
        return result;
    }
}

static class Json
{
    public static void WriteToStdout(object? value)
    {
        if (value is null)
        {
            Console.Out.WriteLine("null");
            return;
        }
        if (value is JsonNode node)
        {
            Console.Out.WriteLine(node.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            return;
        }
        throw new InvalidOperationException(
            $"Json.WriteToStdout requires a JsonNode (got {value.GetType().Name}). " +
            "Anonymous types are not supported under trimming/AOT.");
    }
}

class RaindropCliException : Exception
{
    public int ExitCode { get; }
    public RaindropCliException(string message, int exitCode = 3) : base(message)
    {
        ExitCode = exitCode;
    }
}

static class JsonNum
{
    // Lenient numeric extraction: works regardless of whether the parser
    // recorded the value as Int32, Int64, Double, etc. Returns null when
    // the node is null or the underlying value is not a number.
    public static long? AsLong(JsonNode? node)
    {
        if (node is null) return null;
        try
        {
            var element = node.GetValue<JsonElement>();
            if (element.ValueKind != JsonValueKind.Number) return null;
            if (element.TryGetInt64(out var l)) return l;
            if (element.TryGetDouble(out var d)) return (long)d;
        }
        catch (InvalidOperationException) { }
        try { return node.GetValue<long>(); } catch { }
        try { return (long)node.GetValue<double>(); } catch { }
        return null;
    }
}
