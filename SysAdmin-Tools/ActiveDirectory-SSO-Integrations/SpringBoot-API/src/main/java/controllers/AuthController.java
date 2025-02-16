package com.example.springbootsso.controllers;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    @PostMapping("/login")
    public String authenticateUser(@RequestParam String username, @RequestParam String password) {
        return "User " + username + " authenticated successfully!";
    }
}
