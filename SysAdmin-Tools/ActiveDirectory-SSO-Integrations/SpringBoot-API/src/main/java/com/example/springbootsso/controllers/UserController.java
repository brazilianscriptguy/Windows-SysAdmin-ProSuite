package com.example.springbootsso.controllers;

import com.example.springbootsso.models.UserModel;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/user")
public class UserController {
    
    @GetMapping("/{username}")
    public UserModel getUser(@PathVariable String username) {
        return new UserModel(username, "John Doe", "IT Department");
    }
}
