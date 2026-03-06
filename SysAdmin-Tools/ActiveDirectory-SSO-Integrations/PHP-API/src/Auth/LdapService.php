<?php

declare(strict_types=1);

namespace App\Auth;

use LdapRecord\Connection;
use LdapRecord\Container;

class LdapService
{
    private Connection $connection;

    public function __construct()
    {
        $this->connection = new Connection([
            'hosts'            => [$_ENV['LDAP_HOST']],
            'port'             => (int) ($_ENV['LDAP_PORT'] ?? 389),
            'base_dn'          => $_ENV['LDAP_BASE_DN'],
            'username'         => $_ENV['LDAP_USERNAME'],
            'password'         => $_ENV['LDAP_PASSWORD'],
            'use_ssl'          => filter_var($_ENV['LDAP_USE_SSL'] ?? false, FILTER_VALIDATE_BOOLEAN),
            'use_tls'          => false,
            'version'          => 3,
            'timeout'          => (int) ($_ENV['LDAP_TIMEOUT'] ?? 5),
            'follow_referrals' => false,
        ]);

        Container::addConnection($this->connection);
    }

    public function authenticate(string $username, string $password): ?array
    {
        try {
            $this->connection->auth()->attempt($username, $password);

            $user = $this->connection->query()
                ->where('samaccountname', '=', $username)
                ->orWhere('userprincipalname', '=', $username)
                ->first();

            if (!$user) return null;

            return [
                'username' => $user['samaccountname'][0] ?? $username,
                'name'     => $user['displayname'][0] ?? '',
                'email'    => $user['mail'][0] ?? '',
            ];
        } catch (\Exception $e) {
            error_log("LDAP auth failed: " . $e->getMessage());
            return null;
        }
    }
}
