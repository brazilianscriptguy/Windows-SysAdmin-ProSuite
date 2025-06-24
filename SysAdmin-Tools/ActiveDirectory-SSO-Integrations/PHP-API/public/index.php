<?php
// Path: public/index.php
require_once __DIR__ . '/../env.php';
require_once __DIR__ . '/../config/ldap.php';

session_start();

// Use REMOTE_USER if provided by web server SSO (e.g., Kerberos/NTLM/IIS)
if (!empty($_SERVER['REMOTE_USER'])) {
    $username = basename($_SERVER['REMOTE_USER']); // Remove domain if present

    $ldap = new LDAPAuth();
    $user = $ldap->searchUser($username);

    if ($user) {
        $_SESSION['user'] = [
            'username' => $username,
            'name'     => $user['displayname'][0] ?? '',
            'email'    => $user['mail'][0] ?? ''
        ];
        header('Location: dashboard.php');
        exit;
    }
}

// Fallback to manual login
header('Location: login.php');
exit;
