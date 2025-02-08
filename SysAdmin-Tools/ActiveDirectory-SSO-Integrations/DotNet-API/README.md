# DotNet-API Integration Model

This module demonstrates an ASP.NET Core API that integrates with LDAP for SSO using a generalized configuration.

## Files
- **DotNetSSO.sln:** Visual Studio solution file.
- **DotNetSSO.API/appsettings.json:** Contains the LDAP configuration and logging settings.
- **DotNetSSO.API/Startup.cs:** Configures the ASP.NET Core pipeline and adds a custom LDAP authentication scheme.

## Setup Instructions
1. Set the `LDAP_PASSWORD` environment variable (via environment variables or user secrets).
2. Implement the custom `LdapAuthenticationHandler` to perform LDAP authentication using the settings in `appsettings.json`.
3. Open the solution in Visual Studio or use the .NET CLI to build and run the project.
