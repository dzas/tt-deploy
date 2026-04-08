namespace TrustTunnel.AdminBot.Options;

public sealed class AdminBotOptions
{
    public string BotToken { get; init; } = string.Empty;

    public HashSet<long> AllowedUserIds { get; init; } = [];

    public string TrustTunnelContainerName { get; init; } = "trusttunnel";

    public string EndpointAddress { get; init; } = "tt.example.com:443";

    public string CredentialsPath { get; init; } = "/opt/trusttunnel/credentials.toml";

    public string VpnConfigPathInContainer { get; init; } = "/trusttunnel_endpoint/vpn.toml";

    public string HostsConfigPathInContainer { get; init; } = "/trusttunnel_endpoint/hosts.toml";
}
