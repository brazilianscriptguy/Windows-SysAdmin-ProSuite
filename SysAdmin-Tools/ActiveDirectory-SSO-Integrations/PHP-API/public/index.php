<?php
// File: public/index.php
session_start();
require_once __DIR__ . '/../config/env.php';
require_once __DIR__ . '/../config/ldap.php';

$remote_user = $_SERVER['REMOTE_USER'] ?? null;
$ldap = new LDAPAuth();

if ($remote_user) {
    $username = preg_replace('/^.*?\\/', '', $remote_user); // DOMAIN\\username → username
    $user_info = $ldap->searchUser($username);

    if ($user_info) {
        $_SESSION['user']  = $username;
        $_SESSION['name']  = $user_info['displayname'][0] ?? '';
        $_SESSION['email'] = $user_info['mail'][0] ?? '';
        header('Location: dashboard.php');
        exit;
    }
}

header('Location: login.php');
exit;
