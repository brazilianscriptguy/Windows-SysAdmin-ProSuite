package com.example.springbootsso.models;

public class UserModel {
    private String username;
    private String displayName;
    private String department;

    public UserModel(String username, String displayName, String department) {
        this.username = username;
        this.displayName = displayName;
        this.department = department;
    }
}
