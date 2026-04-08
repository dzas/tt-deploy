using System.Globalization;
using System.Text;
using TrustTunnel.AdminBot.Models;
using TrustTunnel.AdminBot.Options;
using Tomlyn;
using Tomlyn.Serialization;

namespace TrustTunnel.AdminBot.Services;

public sealed class CredentialsService(AdminBotOptions options, ILogger<CredentialsService> logger)
{
    private readonly SemaphoreSlim _mutex = new(1, 1);

    public async Task<IReadOnlyList<ClientCredential>> ListUsersAsync(CancellationToken cancellationToken)
    {
        var users = await ReadUsersUnsafeAsync(cancellationToken);
        return users;
    }

    public async Task<(bool Added, string Message)> AddUserAsync(
        string username,
        string password,
        CancellationToken cancellationToken)
    {
        await _mutex.WaitAsync(cancellationToken);
        try
        {
            var users = await ReadUsersUnsafeAsync(cancellationToken);
            if (users.Any(user => string.Equals(user.Username, username, StringComparison.Ordinal)))
            {
                return (false, $"User '{username}' already exists.");
            }

            users.Add(new ClientCredential(username, password));
            await BackupAndWriteUnsafeAsync(users, cancellationToken);

            logger.LogInformation("Added TrustTunnel user '{Username}'", username);
            return (true, $"User '{username}' added.");
        }
        finally
        {
            _mutex.Release();
        }
    }

    public async Task<(bool Removed, string Message)> RemoveUserAsync(
        string username,
        CancellationToken cancellationToken)
    {
        await _mutex.WaitAsync(cancellationToken);
        try
        {
            var users = await ReadUsersUnsafeAsync(cancellationToken);
            var removedCount = users.RemoveAll(user => string.Equals(user.Username, username, StringComparison.Ordinal));

            if (removedCount == 0)
            {
                return (false, $"User '{username}' not found.");
            }

            await BackupAndWriteUnsafeAsync(users, cancellationToken);

            logger.LogInformation("Removed TrustTunnel user '{Username}'", username);
            return (true, $"User '{username}' removed.");
        }
        finally
        {
            _mutex.Release();
        }
    }

    private async Task<List<ClientCredential>> ReadUsersUnsafeAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(options.CredentialsPath))
        {
            return [];
        }

        var text = await File.ReadAllTextAsync(options.CredentialsPath, cancellationToken);
        if (string.IsNullOrWhiteSpace(text))
        {
            return [];
        }

        var document = TomlSerializer.Deserialize<CredentialsDocument>(text) ?? new CredentialsDocument();
        return document.Client
            .Where(static row => !string.IsNullOrWhiteSpace(row.Username))
            .Select(static row => new ClientCredential(row.Username, row.Password))
            .ToList();
    }

    private async Task BackupAndWriteUnsafeAsync(List<ClientCredential> users, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(options.CredentialsPath) ?? "/");

        if (File.Exists(options.CredentialsPath))
        {
            var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture);
            var backupPath = $"{options.CredentialsPath}.bak.{timestamp}";
            File.Copy(options.CredentialsPath, backupPath, overwrite: false);
        }

        var rendered = RenderCredentials(users);
        var tempPath = $"{options.CredentialsPath}.tmp";

        await File.WriteAllTextAsync(tempPath, rendered, cancellationToken);
        File.Move(tempPath, options.CredentialsPath, overwrite: true);
    }

    private static string RenderCredentials(IEnumerable<ClientCredential> users)
    {
        var sb = new StringBuilder();
        var first = true;

        foreach (var user in users)
        {
            if (!first)
            {
                sb.AppendLine();
            }

            sb.AppendLine("[[client]]");
            sb.Append("username = \"").Append(EscapeTomlString(user.Username)).AppendLine("\"");
            sb.Append("password = \"").Append(EscapeTomlString(user.Password)).AppendLine("\"");

            first = false;
        }

        return sb.ToString();
    }

    private static string EscapeTomlString(string value)
    {
        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal)
            .Replace("\t", "\\t", StringComparison.Ordinal);
    }

    private sealed class CredentialsDocument
    {
        [TomlPropertyName("client")]
        public List<ClientCredentialToml> Client { get; init; } = [];
    }

    private sealed class ClientCredentialToml
    {
        [TomlPropertyName("username")]
        public string Username { get; init; } = string.Empty;

        [TomlPropertyName("password")]
        public string Password { get; init; } = string.Empty;
    }
}
