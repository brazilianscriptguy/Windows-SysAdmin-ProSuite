<?php
// Path: public/dashboard.php
session_start();

if (!isset($_SESSION['user'])) {
    header('Location: login.php');
    exit;
}

$user = $_SESSION['user'];
?>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Dashboard - PHP SSO</title>
</head>
<body>
    <h1>Welcome, <?= htmlspecialchars($user['name']) ?></h1>
    <p>Email: <?= htmlspecialchars($user['email']) ?></p>
    <p>Username: <?= htmlspecialchars($user['username']) ?></p>
    <a href="logout.php">Logout</a>
</body>
</html>
