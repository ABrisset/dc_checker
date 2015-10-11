# dc_checker
SEO Ruby script to compute Salton cosine and Jaccard coefficient at a glance.
To make it work, just add a `config` directory and create a `database.yml` file providing your mysql configuration. Such as :

``` yml
development:
  host: localhost
  username: your_username
  password: your_password
  encoding: utf8
  port:
```

Then just run ./checker.rb followed by a URL and a database name.
