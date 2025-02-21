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
assuming your domain is called: `archetype.myserver.com` and `api.archetype.myserver.com`, 
Make sure to add `A records` that point to your server before continuing.

To generate TLS certificates, run the following commands:

```bash
>>> make up-background
# create certificate for client and admin websites
>>> make certbot
```
Make sure to instal `make` first using `sudo apt install make` if you're on ubuntu or look for equivalent commands for your operating system.

### Enable TLS on the server nginx 
In your compose.yaml file, comment out line 51:  
`- ./nginx/no_ssl.conf...ro`

and uncomment line 52:  
`- ./nginx/ssl.conf...ro`


Then continue with the following commands:  
```bash
>>> make down
>>> make up-background
```
