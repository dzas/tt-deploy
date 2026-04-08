using TrustTunnel.AdminBot.Options;
using TrustTunnel.AdminBot.Services;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();

    var allowedUserIds = (config["TELEGRAM_ALLOWED_USER_IDS"] ?? string.Empty)
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Select(static value => long.TryParse(value, out var parsed) ? parsed : 0)
        .Where(static value => value != 0)
        .ToHashSet();

    return new AdminBotOptions
    {
        BotToken = config["TELEGRAM_BOT_TOKEN"] ?? string.Empty,
        AllowedUserIds = allowedUserIds,
        TrustTunnelContainerName = config["TT_CONTAINER_NAME"] ?? "trusttunnel",
        EndpointAddress = config["TT_ENDPOINT_ADDRESS"] ?? "tt.example.com:443",
        CredentialsPath = config["TT_CREDENTIALS_PATH"] ?? "/opt/trusttunnel/credentials.toml",
        VpnConfigPathInContainer = config["TT_VPN_CONFIG_PATH_IN_CONTAINER"] ?? "/trusttunnel_endpoint/vpn.toml",
        HostsConfigPathInContainer = config["TT_HOSTS_CONFIG_PATH_IN_CONTAINER"] ?? "/trusttunnel_endpoint/hosts.toml",
    };
});

builder.Services.AddSingleton<CommandRunner>();
builder.Services.AddSingleton<CredentialsService>();
builder.Services.AddSingleton<TrustTunnelEndpointService>();
builder.Services.AddHostedService<TelegramBotWorker>();

var app = builder.Build();

var options = app.Services.GetRequiredService<AdminBotOptions>();
if (string.IsNullOrWhiteSpace(options.BotToken))
{
    throw new InvalidOperationException("TELEGRAM_BOT_TOKEN is required.");
}

if (options.AllowedUserIds.Count == 0)
{
    throw new InvalidOperationException("TELEGRAM_ALLOWED_USER_IDS is required (comma-separated user IDs).");
}

await app.RunAsync();
