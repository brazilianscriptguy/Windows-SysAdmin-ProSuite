<?php

declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';

use App\Auth\LdapService;

session_start([
    'cookie_secure'   => isset($_SERVER['HTTPS']),
    'cookie_httponly' => true,
    'cookie_samesite' => 'Strict',
    'use_strict_mode' => true,
]);

if (!empty($_SESSION['user'])) {
    header('Location: dashboard.php');
    exit;
}

// Try transparent SSO (REMOTE_USER)
if (!empty($_SERVER['REMOTE_USER'])) {
    $username = basename($_SERVER['REMOTE_USER']); // remove domain prefix if present

    $ldap = new LdapService();
    $userData = $ldap->searchByUsername($username);

    if ($userData) {
        $_SESSION['user'] = $userData;
        header('Location: dashboard.php');
        exit;
    }
}

// No SSO → go to login
header('Location: login.php');
exit;
