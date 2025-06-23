<?php
// File: public/index.php
session_start();

if (isset($_SERVER['REMOTE_USER'])) {
    $_SESSION['user'] = $_SERVER['REMOTE_USER'];
    header('Location: dashboard.php');
    exit;
}

// If SSO not detected, redirect to manual login
header('Location: login.php');
exit;
