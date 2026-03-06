<?php

declare(strict_types=1);

namespace App\Auth;

use Dotenv\Dotenv;
use LdapRecord\Connection;
use LdapRecord\Container;
use LdapRecord\Models\ActiveDirectory\User;

class LdapService
{
    private Connection $connection;

    public function __construct()
    {
        $dotenv = Dotenv::createImmutable(dirname(__DIR__, 2));
        $dotenv->safeLoad();

        $config = [
            'hosts'            => [$_ENV['LDAP_HOST'] ?? 'localhost'],
            'port'             => (int) ($_ENV['LDAP_PORT'] ?? 389),
            'base_dn'          => $_ENV['LDAP_BASE_DN'] ?? '',
            'username'         => $_ENV['LDAP_USERNAME'] ?? '',
            'password'         => $_ENV['LDAP_PASSWORD'] ?? '',
            'use_ssl'          => filter_var($_ENV['LDAP_USE_SSL'] ?? false, FILTER_VALIDATE_BOOLEAN),
            'use_tls'          => false,
            'version'          => 3,
            'timeout'          => (int) ($_ENV['LDAP_TIMEOUT'] ?? 5),
            'follow_referrals' => false,
        ];

        $this->connection = new Connection($config);
        Container::addConnection($this->connection);
    }

    public function authenticate(string $username, string $password): ?array
    {
        try {
            // Attempt bind with user credentials
            $this->connection->auth()->attempt($username, $password);

            $user = $this->connection->query()
                ->where('samaccountname', '=', $username)
                ->orWhere('userprincipalname', '=', $username)
                ->select(['displayname', 'mail', 'samaccountname', 'userprincipalname'])
                ->first();

            if (!$user) {
                return null;
            }

            // Optional: filter out non-user objects (e.g. inetOrgPerson)
            if (isset($user['objectclass']) && in_array('inetOrgPerson', $user['objectclass'])) {
                return null;
            }

            return [
                'username' => $user['samaccountname'][0] ?? $username,
                'name'     => $user['displayname'][0] ?? '',
                'email'    => $user['mail'][0] ?? '',
            ];
        } catch (\Exception $e) {
            error_log("LDAP auth error: " . $e->getMessage());
            return null;
        }
    }

    public function searchByUsername(string $username): ?array
    {
        try {
            $user = $this->connection->query()
                ->where('samaccountname', '=', $username)
                ->orWhere('userprincipalname', '=', $username)
                ->first();

            if (!$user) {
                return null;
            }

            return [
                'username' => $user['samaccountname'][0] ?? $username,
                'name'     => $user['displayname'][0] ?? '',
                'email'    => $user['mail'][0] ?? '',
            ];
        } catch (\Exception $e) {
            error_log("LDAP search error: " . $e->getMessage());
            return null;
        }
    }
}
