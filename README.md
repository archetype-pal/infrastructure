# infrastructure
Contains deployment guidelines

The recommended way to install Archetype3 on your machine is using `docker compose`.

The `compose.yaml` file here is already prepared using production configuration.

**To set up archetype3 on your production environment, you need to do the following**

```bash
>>> git clone git@github.com:archetype-pal/infrastructure.git

>>> cd infrastructure
>>> docker compose up -d
```

### Configure your environment variables
create a new file `env_file` and fill it with the required variables. A working example can be found [here](./env_file.example)

### Setup the TLS certificates on your server
To generate TLS certificates, run the following two commands  
assuming your domain is called: `archetype.myserver.com`  
Make sure to add `A records` that point to your server before continuing.

```bash
# create certificate for website
>>> docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d archetype.myserver.com
# create certificate for admin site
>>> docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d api.archetype.myserver.com
```

### Enable TLS on the server nginx 
In your nginx.conf file, you will find 4 lines for `ssl_certificates` commented out.  
Uncomment these lines, then continue with the following commands:  
```bash
>>> docker compose down
>>> docker compose up -d
```
