package com.example.springbootsso.controllers;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    @PostMapping("/login")
    public ResponseEntity<String> authenticate(@RequestParam String username, @RequestParam String password) {
        // LDAP authentication handled by Spring Security
        return ResponseEntity.ok("Authentication successful");
    }
}
