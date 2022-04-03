vcl 4.1;

import std;

backend default {
        .host = "127.0.0.1";
        .port = "80";
        .probe = {
                .url = "/";
                .interval = 5s;
                .timeout = 3s;
                .window = 5;
                .threshold = 3;
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
        
        if ( std.healthy(req.backend_hint) ) {
                set req.grace = 30s;
        } else {
                set req.grace = 10m;
        }
        
        if ( req.url ~ "^/admin" ) {
                unset req.http.Cookie;
        }
        
        if ( req.method == "PURGE" ) {
                if ( !client.ip ~ purge ) {
                        return (synth(405, "Not allowed"));
                }
                return (lookup);
        }
}

sub vcl_hit {
    if (obj.ttl >= 0s) {
        // A pure unadultered hit, deliver it
        return (deliver);
    }
    if (obj.ttl + obj.grace > 0s) {
        // Object is in grace, deliver it
        // Automatically triggers a background fetch
        return (deliver);
    }
    // fetch & deliver once we get the result
    return (fetch);
}

sub vcl_miss {
        if ( req.method == "PURGE" ) {
                return (purge);
                return (synth(200, "Purged (Miss)."));
        }
}

sub vcl_backend_response {
        set beresp.grace = 30m;
        if ( req.url ~ "^/admin" ) {
                unset beresp.http.Set-Cookie;
        }
}