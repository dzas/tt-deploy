using TrustTunnel.AdminBot.Models;
using TrustTunnel.AdminBot.Options;

namespace TrustTunnel.AdminBot.Services;

public sealed class TrustTunnelEndpointService(
    AdminBotOptions options,
    CommandRunner commandRunner,
    ILogger<TrustTunnelEndpointService> logger)
{
    public async Task<GeneratedLinks> GenerateClientLinksAsync(string username, CancellationToken cancellationToken)
    {
        var args = new List<string>
        {
            "exec",
            options.TrustTunnelContainerName,
            "/bin/trusttunnel_endpoint",
            options.VpnConfigPathInContainer,
            options.HostsConfigPathInContainer,
            "-c",
            username,
            "-a",
            options.EndpointAddress,
        };

        var result = await commandRunner.RunAsync("docker", args, cancellationToken);
        if (!result.IsSuccess)
        {
            throw new InvalidOperationException($"Failed to generate link: {result.StandardError}");
        }

        var deepLink = string.Empty;
        var qrPageLink = string.Empty;

        foreach (var line in result.StandardOutput.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            if (line.StartsWith("tt://", StringComparison.Ordinal))
            {
                deepLink = line;
                continue;
            }

            if (line.Contains("https://trusttunnel.org/qr.html#tt=", StringComparison.Ordinal))
            {
                qrPageLink = line;
            }
        }

        if (string.IsNullOrWhiteSpace(deepLink))
        {
            throw new InvalidOperationException("Deep-link was not found in trusttunnel_endpoint output.");
        }

        logger.LogInformation("Generated links for user '{Username}'", username);
        return new GeneratedLinks(deepLink, qrPageLink);
    }

    public async Task RestartContainerAsync(CancellationToken cancellationToken)
    {
        var args = new[] { "restart", options.TrustTunnelContainerName };
        var result = await commandRunner.RunAsync("docker", args, cancellationToken);
        if (!result.IsSuccess)
        {
            throw new InvalidOperationException($"Failed to restart TrustTunnel container: {result.StandardError}");
        }
    }

    public async Task<string> GetContainerStatusAsync(CancellationToken cancellationToken)
    {
        var args = new[]
        {
            "inspect",
            options.TrustTunnelContainerName,
            "--format",
            "{{.State.Status}}",
        };

        var result = await commandRunner.RunAsync("docker", args, cancellationToken);
        if (!result.IsSuccess)
        {
            return $"unknown ({result.StandardError})";
        }

        return string.IsNullOrWhiteSpace(result.StandardOutput) ? "unknown" : result.StandardOutput;
    }
}
