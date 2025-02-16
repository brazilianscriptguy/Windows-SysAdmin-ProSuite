package com.example.springbootsso.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.authentication.builders.AuthenticationManagerBuilder;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.ldap.authentication.ad.ActiveDirectoryLdapAuthenticationProvider;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    public void configure(AuthenticationManagerBuilder auth) throws Exception {
        auth.authenticationProvider(new ActiveDirectoryLdapAuthenticationProvider(
                "headq.scriptguy", "ldap://ldap.headq.scriptguy:3268"));
    }
}
