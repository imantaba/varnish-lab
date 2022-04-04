vcl 4.1;

import std;
import directors;


backend default {
        .host = "nginx";
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
                        return (synth(405, "This IP is not allowed to send PURGE requests."));
                }
                return (purge);
        }
}

sub vcl_hit {
  # Called when a cache lookup is successful.

  if (obj.ttl >= 0s) {
    # A pure unadultered hit, deliver it
    return (deliver);
  }

  # We have no fresh fish. Lets look at the stale ones.
  if (std.healthy(req.backend_hint)) {
    # Backend is healthy. Limit age to 10s.
    if (obj.ttl + 10s > 0s) {
      #set req.http.grace = "normal(limited)";
      return (deliver);
    }
  } else {
    # backend is sick - use full grace
      if (obj.ttl + obj.grace > 0s) {
        #set req.http.grace = "full";
        return (deliver);
      }
  }
}


sub vcl_miss {
  # Called after a cache lookup if the requested document was not found in the cache. Its purpose
  # is to decide whether or not to attempt to retrieve the document from the backend, and which
  # backend to use.

  return (fetch);
}

sub vcl_backend_response {
  # Called after the response headers has been successfully retrieved from the backend.

  # Pause ESI request and remove Surrogate-Control header
  if (beresp.http.Surrogate-Control ~ "ESI/1.0") {
    unset beresp.http.Surrogate-Control;
    set beresp.do_esi = true;
  }

  # Enable cache for all static files
  # The same argument as the static caches from above: monitor your cache size, if you get data nuked out of it, consider giving up the static file cache.
  # Before you blindly enable this, have a read here: https://ma.ttias.be/stop-caching-static-files/
  if (bereq.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|otf|ogg|ogm|opus|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
    unset beresp.http.set-cookie;
  }

  # Large static files are delivered directly to the end-user without
  # waiting for Varnish to fully read the file first.
  # Varnish 4 fully supports Streaming, so use streaming here to avoid locking.
  if (bereq.url ~ "^[^?]*\.(7z|avi|bz2|flac|flv|gz|mka|mkv|mov|mp3|mp4|mpeg|mpg|ogg|ogm|opus|rar|tar|tgz|tbz|txz|wav|webm|xz|zip)(\?.*)?$") {
    unset beresp.http.set-cookie;
    set beresp.do_stream = true;  # Check memory usage it'll grow in fetch_chunksize blocks (128k by default) if the backend doesn't send a Content-Length header, so only enable it for big objects
  }

  # Sometimes, a 301 or 302 redirect formed via Apache's mod_rewrite can mess with the HTTP port that is being passed along.
  # This often happens with simple rewrite rules in a scenario where Varnish runs on :80 and Apache on :8080 on the same box.
  # A redirect can then often redirect the end-user to a URL on :8080, where it should be :80.
  # This may need finetuning on your setup.
  #
  # To prevent accidental replace, we only filter the 301/302 redirects for now.
  if (beresp.status == 301 || beresp.status == 302) {
    set beresp.http.Location = regsub(beresp.http.Location, ":[0-9]+", "");
  }

  # Set 2min cache if unset for static files
  if (beresp.ttl <= 0s || beresp.http.Set-Cookie || beresp.http.Vary == "*") {
    set beresp.ttl = 120s; # Important, you shouldn't rely on this, SET YOUR HEADERS in the backend
    set beresp.uncacheable = true;
    return (deliver);
  }

  # Don't cache 50x responses
  if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504) {
    return (abandon);
  }

  # Allow stale content, in case the backend goes down.
  # make Varnish keep all objects for 6 hours beyond their TTL
  # this means that varnish will actually allow the content to remain in the cache for 6 hour after expiry time has passed and this setting applies at the
  # time that the content is loaded from backend but even that content is kept in the cache varnish actually will not send it to the users if it passed the 
  # expiry time
  set beresp.grace = 6h;

  return (deliver);
}


sub vcl_purge {
  # Only handle actual PURGE HTTP methods, everything else is discarded
  if (req.method == "PURGE") {
    # restart request
    set req.http.X-Purge = "Yes";
    return(restart);
  }
}