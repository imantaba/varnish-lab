vcl 4.1;


backend default {
        .host = "127.0.0.1";
        .port = "80";
        .probe = {
                .url = "/";
                .interval = 5s;
                .timeout = 3s;
                .window = 5;
                .threshhold = 3;
        }
}

acl purge {
        "127.0.0.1";
        "192.168.43.171";
        "varnish";
}

sub vcl_recv {

        if ( req.http.Host == "www.beta.garandwebtech.com" ) {
                set req.http.Host = "beta.garandwebtech.com";
        }
        
        if ( req.backend.healthy) {
                set req.grace = 30s;
        } else {
                set req.grace = 10m ;
        }
        
        if ( req.url ~ "^/admin") {
                unset req.http.Cookie;
        }
        
        if ( req.request == "PURGE" ) {
                if ( !client.p ~ purge ) {
                        error 405 "Not allowed to purge";
                }
                return (lookup);
        }
}

sub vcl_hit {
        if ( req.request == "PURGE") {
                purge;
                error 200 "Purged (Hit).";
        }
}

sub vcl_miss {
        if ( req.request == "PURGE") {
                purge;
                error 200 "Purged (Miss).";
        }
}

sub_vcl_fetch {
        set beresp.grace = 30m;
        if ( req.url ~ "^/admin" ) {
                unset beresp.http.Set-Cookie;
        }
}