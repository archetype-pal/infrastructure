# infrastructure
Contains deployment guidelines

The recommended way to install Archetype3 on your machine is using docker compose.

The `compose.yaml` file here is already prepared using production configuration. However, it requries the user to configure their own reverse proxy. 

Along with the compose file, you need to add a file with environment variables called `env_file`. An example file is already prepared for you in `env_file.example`


## ToDo
- [ ] Add nginx to the compose file to save more configuration time for users
