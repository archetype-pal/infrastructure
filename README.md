# infrastructure
This repository contains instructions for setting up the Archetype server on your machine.   
Following the instructions require a little bit of a technical background.

**For all instructions, you will require a terminal window open**

## Prerequisites 
- `Xcode Command Line Tools` Required only for mac
  - Open a terminal and run `xcode-select --install`
- `Git`: Install from https://git-scm.com/downloads
- `Docker`: Install from https://docs.docker.com/engine/install/
- `Makefile`: Not included with windows! User is encouraged to install Makefile on windows independently.


## Steps

1. Get a copy of the needed files from github:
    ```bash 
    >>> git clone git@github.com:archetype-pal/infrastructure.git

    # Navigate to the project directory
    >>> cd infrastructure
    ```

2. Adust the project configuration to suit your needs.  
    Create a new file `env_file` and fill it with the required variables. A working example can be found [here](./env_file.example).

3. Run the project in the background 
    ```bash
    >>> make up-background
    ```
4. Run the database migrations
    ```bash
    >>> make migrate
    ```
5. Open the website in your browser by navigating to `http://localhost`


## Setup the TLS certificates on your server
This is *optional* for those who want to deploy their website securely using `https` on a custom domain.

assuming your domain is called: `archetype.myserver.com`,  
start by adding an `A record` that points to your server before continuing.

To generate TLS certificates, run the following commands:
```bash
>>> make certbot
```

### Enable TLS on the server nginx 
After running the above command. You should now have the cert folder populated with
the needed files.  
Open the file `nginx.conf` and uncomment the certificate files as explained there. 

Then run the following command:  
```bash
>>> docker compose restart nginx
```

## troubleshooting
Since this setup process is very delicate, it's important to know how to check the logs.  
run the following command
```bash
>>> docker compose logs -f
```
to see a real-time view over the logs.