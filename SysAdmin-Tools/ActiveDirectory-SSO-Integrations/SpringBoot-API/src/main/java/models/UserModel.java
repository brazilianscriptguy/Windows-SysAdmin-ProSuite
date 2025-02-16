package com.example.springbootsso.models;

public class UserModel {
    private String username;
    private String displayName;
    private String email;

    public UserModel(String username, String displayName, String email) {
        this.username = username;
        this.displayName = displayName;
        this.email = email;
    }

    public String getUsername() { return username; }
    public String getDisplayName() { return displayName; }
    public String getEmail() { return email; }
}
