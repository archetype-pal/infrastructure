# infrastructure
Contains deployment guidelines

The recommended way to install Archetype3 on your machine is using `docker compose`.

The `compose.yaml` file here is already prepared using production configuration.

**To set up archetype3 on your production environment, you need to do the following**

```bash
>>> git clone git@github.com:archetype-pal/infrastructure.git

>>> cd infrastructure
```

### Configure your environment variables
create a new file `env_file` and fill it with the required variables. A working example can be found [here](./env_file.example)


### Setup the TLS certificates on your server
To generate TLS certificates, run the following commands  
assuming your domain is called: `archetype.myserver.com` and `api.archetype.myserver.com`, 
Make sure to add `A records` that point to your server before continuing.

```bash
>>> docker compose up -d
# create certificate for client website
>>> docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d $APP_DOMAIN
# create certificate for admin website and API
>>> docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d $API_DOMAIN
```

### Enable TLS on the server nginx 
In your compose.yaml file, comment out line 51:  
`- ./nginx/no_ssl.conf:/etc/nginx/nginx.conf:ro`

and uncomment line 52:  
`- ./nginx/ssl.conf:/etc/nginx/nginx.conf:ro`


Then continue with the following commands:  
```bash
>>> docker compose down
>>> docker compose up -d
```
