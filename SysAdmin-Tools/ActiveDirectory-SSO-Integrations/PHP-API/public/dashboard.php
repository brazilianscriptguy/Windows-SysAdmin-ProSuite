<?php
// File: public/dashboard.php
session_start();

if (!isset($_SESSION['user'])) {
    header('Location: login.php');
    exit;
}

$user = $_SESSION['user'];
$name = $_SESSION['name'] ?? '';
$email = $_SESSION['email'] ?? '';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Dashboard</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css">
</head>
<body class="container mt-5">
    <h2>Welcome, <?= htmlspecialchars($name) ?>!</h2>
    <p><strong>User:</strong> <?= htmlspecialchars($user) ?></p>
    <p><strong>Email:</strong> <?= htmlspecialchars($email) ?></p>
    <a href="logout.php" class="btn btn-danger">Logout</a>
</body>
</html>
