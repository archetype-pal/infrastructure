# infrastructure
Contains deployment guidelines

The recommended way to install Archetype3 on your machine is using `docker compose`.

The `compose.yaml` file here is already prepared using production configuration.

**To set up archetype3 on your production environment, you need to do the following**

```bash
>>> git clone git@github.com:archetype-pal/infrastructure.git

>>> cd infrastructure
```

### Setup the TLS certificates on your server
To generate TLS certificates, run the following two commands  
assuming your domain is called: `archetype.myserver.com`
```bash
# create certificate for website
>>> docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d archetype.myserver.com
# create certificate for admin site
>>> docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d api.archetype.myserver.com
```

### Configure your environment variables
create a new file `env_file` and fill it with the required variables. A working example can be found [here](./env_file.example)

### Last step
```bash
>>> docker compose down
>>> docker compose up -d
```