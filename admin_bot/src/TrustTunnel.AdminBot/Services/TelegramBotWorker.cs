using System.Text;
using TrustTunnel.AdminBot.Options;
using Telegram.Bot;
using Telegram.Bot.Polling;
using Telegram.Bot.Types;
using Telegram.Bot.Types.Enums;

namespace TrustTunnel.AdminBot.Services;

public sealed class TelegramBotWorker(
    AdminBotOptions options,
    CredentialsService credentialsService,
    TrustTunnelEndpointService endpointService,
    ILogger<TelegramBotWorker> logger) : BackgroundService
{
    private readonly ITelegramBotClient _botClient = new TelegramBotClient(options.BotToken);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var me = await _botClient.GetMe(stoppingToken);
        logger.LogInformation("Admin bot started as @{Username} ({Id})", me.Username, me.Id);

        var receiverOptions = new ReceiverOptions
        {
            AllowedUpdates = [UpdateType.Message],
        };

        _botClient.StartReceiving(
            updateHandler: HandleUpdateAsync,
            errorHandler: HandleErrorAsync,
            receiverOptions: receiverOptions,
            cancellationToken: stoppingToken);

        await Task.Delay(Timeout.Infinite, stoppingToken);
    }

    private async Task HandleUpdateAsync(
        ITelegramBotClient botClient,
        Update update,
        CancellationToken cancellationToken)
    {
        var message = update.Message;
        if (message?.Text is null || message.From is null)
        {
            return;
        }

        if (!options.AllowedUserIds.Contains(message.From.Id))
        {
            await botClient.SendMessage(
                chatId: message.Chat.Id,
                text: "Access denied.",
                cancellationToken: cancellationToken);
            return;
        }

        var text = message.Text.Trim();
        var command = text.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (command.Length == 0)
        {
            return;
        }

        logger.LogInformation("Command from {UserId}: {CommandText}", message.From.Id, text.Split(' ')[0]);

        try
        {
            switch (command[0].ToLowerInvariant())
            {
                case "/start":
                case "/help":
                    await SendHelpAsync(botClient, message.Chat.Id, cancellationToken);
                    break;

                case "/list":
                    await SendUsersAsync(botClient, message.Chat.Id, cancellationToken);
                    break;

                case "/link":
                    await SendLinkAsync(botClient, message.Chat.Id, command, cancellationToken);
                    break;

                case "/add":
                    await AddUserAsync(botClient, message.Chat.Id, command, cancellationToken);
                    break;

                case "/del":
                    await RemoveUserAsync(botClient, message.Chat.Id, command, cancellationToken);
                    break;

                case "/health":
                    await SendHealthAsync(botClient, message.Chat.Id, cancellationToken);
                    break;

                default:
                    await botClient.SendMessage(
                        chatId: message.Chat.Id,
                        text: "Unknown command. Use /help.",
                        cancellationToken: cancellationToken);
                    break;
            }
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Failed to process command {Command}", command[0]);
            await botClient.SendMessage(
                chatId: message.Chat.Id,
                text: $"Error: {exception.Message}",
                cancellationToken: cancellationToken);
        }
    }

    private static Task HandleErrorAsync(ITelegramBotClient _, Exception exception, CancellationToken __)
    {
        Console.Error.WriteLine(exception);
        return Task.CompletedTask;
    }

    private static async Task SendHelpAsync(ITelegramBotClient botClient, long chatId, CancellationToken cancellationToken)
    {
        const string helpText = """
Commands:
/help - Show this help
/list - List users from credentials.toml
/link <username> - Generate tt:// and QR link
/add <username> <password> - Add user and restart TrustTunnel
/del <username> - Remove user and restart TrustTunnel
/health - Show TrustTunnel container status
""";

        await botClient.SendMessage(chatId: chatId, text: helpText, cancellationToken: cancellationToken);
    }

    private async Task SendUsersAsync(ITelegramBotClient botClient, long chatId, CancellationToken cancellationToken)
    {
        var users = await credentialsService.ListUsersAsync(cancellationToken);
        if (users.Count == 0)
        {
            await botClient.SendMessage(chatId: chatId, text: "No users in credentials.toml.", cancellationToken: cancellationToken);
            return;
        }

        var text = new StringBuilder();
        text.AppendLine($"Users: {users.Count}");
        foreach (var user in users)
        {
            text.Append("- ").AppendLine(user.Username);
        }

        await botClient.SendMessage(chatId: chatId, text: text.ToString(), cancellationToken: cancellationToken);
    }

    private async Task SendLinkAsync(
        ITelegramBotClient botClient,
        long chatId,
        IReadOnlyList<string> command,
        CancellationToken cancellationToken)
    {
        if (command.Count != 2)
        {
            await botClient.SendMessage(chatId: chatId, text: "Usage: /link <username>", cancellationToken: cancellationToken);
            return;
        }

        var username = command[1];
        var links = await endpointService.GenerateClientLinksAsync(username, cancellationToken);

        var text = new StringBuilder();
        text.AppendLine($"User: {username}");
        text.AppendLine(links.DeepLink);
        if (!string.IsNullOrWhiteSpace(links.QrPageLink))
        {
            text.AppendLine().AppendLine(links.QrPageLink);
        }

        await botClient.SendMessage(chatId: chatId, text: text.ToString(), cancellationToken: cancellationToken);
    }

    private async Task AddUserAsync(
        ITelegramBotClient botClient,
        long chatId,
        IReadOnlyList<string> command,
        CancellationToken cancellationToken)
    {
        if (command.Count != 3)
        {
            await botClient.SendMessage(chatId: chatId, text: "Usage: /add <username> <password>", cancellationToken: cancellationToken);
            return;
        }

        var username = command[1];
        var password = command[2];

        var result = await credentialsService.AddUserAsync(username, password, cancellationToken);
        if (!result.Added)
        {
            await botClient.SendMessage(chatId: chatId, text: result.Message, cancellationToken: cancellationToken);
            return;
        }

        await endpointService.RestartContainerAsync(cancellationToken);
        await botClient.SendMessage(
            chatId: chatId,
            text: $"{result.Message} TrustTunnel restarted.",
            cancellationToken: cancellationToken);
    }

    private async Task RemoveUserAsync(
        ITelegramBotClient botClient,
        long chatId,
        IReadOnlyList<string> command,
        CancellationToken cancellationToken)
    {
        if (command.Count != 2)
        {
            await botClient.SendMessage(chatId: chatId, text: "Usage: /del <username>", cancellationToken: cancellationToken);
            return;
        }

        var username = command[1];

        var result = await credentialsService.RemoveUserAsync(username, cancellationToken);
        if (!result.Removed)
        {
            await botClient.SendMessage(chatId: chatId, text: result.Message, cancellationToken: cancellationToken);
            return;
        }

        await endpointService.RestartContainerAsync(cancellationToken);
        await botClient.SendMessage(
            chatId: chatId,
            text: $"{result.Message} TrustTunnel restarted.",
            cancellationToken: cancellationToken);
    }

    private async Task SendHealthAsync(ITelegramBotClient botClient, long chatId, CancellationToken cancellationToken)
    {
        var users = await credentialsService.ListUsersAsync(cancellationToken);
        var status = await endpointService.GetContainerStatusAsync(cancellationToken);

        var text = $"Container '{options.TrustTunnelContainerName}': {status}\nUsers: {users.Count}";
        await botClient.SendMessage(chatId: chatId, text: text, cancellationToken: cancellationToken);
    }
}
