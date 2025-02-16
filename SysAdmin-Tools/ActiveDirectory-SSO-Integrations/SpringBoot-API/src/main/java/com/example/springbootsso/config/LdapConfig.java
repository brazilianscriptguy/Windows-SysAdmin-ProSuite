package com.example.springbootsso.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.ldap.core.LdapTemplate;
import org.springframework.ldap.core.support.LdapContextSource;

@Configuration
public class LdapConfig {

    @Bean
    public LdapContextSource ldapContextSource() {
        LdapContextSource contextSource = new LdapContextSource();
        contextSource.setUrl("ldap://ldap.headq.scriptguy:3268");
        contextSource.setBase("dc=headq,dc=scriptguy");
        contextSource.setUserDn("ad-sso-authentication@headq");
        contextSource.setPassword(System.getenv("LDAP_PASSWORD"));
        contextSource.setPooled(true);
        return contextSource;
    }

    @Bean
    public LdapTemplate ldapTemplate() {
        return new LdapTemplate(ldapContextSource());
    }
}
