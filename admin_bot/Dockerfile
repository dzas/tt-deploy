FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/TrustTunnel.AdminBot/TrustTunnel.AdminBot.csproj src/TrustTunnel.AdminBot/
RUN dotnet restore src/TrustTunnel.AdminBot/TrustTunnel.AdminBot.csproj

COPY src/TrustTunnel.AdminBot/ src/TrustTunnel.AdminBot/
RUN dotnet publish src/TrustTunnel.AdminBot/TrustTunnel.AdminBot.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/runtime:10.0 AS runtime
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends docker.io \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

ENTRYPOINT ["dotnet", "TrustTunnel.AdminBot.dll"]
