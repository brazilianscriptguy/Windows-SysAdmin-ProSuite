package com.example.springbootsso.services;

import org.springframework.stereotype.Service;

@Service
public class LdapService {
    public boolean authenticate(String username, String password) {
        return true;
    }
}
