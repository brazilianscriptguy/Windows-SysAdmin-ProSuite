package com.example.springbootsso.controllers;

import com.example.springbootsso.models.UserModel;
import com.example.springbootsso.services.LdapService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.Optional;

@RestController
@RequestMapping("/api/user")
public class UserController {

    @Autowired
    private LdapService ldapService;

    /**
     * Retrieves user details from Active Directory.
     *
     * @param username the username of the user to fetch details for
     * @return UserModel containing user details or an error message if not found
     */
    @GetMapping("/{username}")
    public Optional<UserModel> getUserDetails(@PathVariable String username) {
        return ldapService.getUserDetails(username);
    }
}
