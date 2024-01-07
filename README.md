# CRunner-Web
The web server behind the cloud-runner web interface

# Description
CRunner is the webserver backend for https://github.com/TH3-F001/cloud-runner. It is meant to be deployed on a linode via the cloud-runner tool.
CRunner runs scripts on the client's behalf, displays progress, statistics, and diagnostic information, and returns results once the client supplied script has completed.
CRunner serves two kinds of interfaces:
- A simple API for getting the user-supplied script, communicating script status, and returning output
- A simple web interface that displays a live WebSockets feed of the script log and some other live diagnostics and statistics. 

## Purpose
The idea behind Crunner is to offload intensive tasks (particularly network intensive tasks) to a Linode in the cloud with high bandwidth capabilities.



## Features 
- HTTPS-only Communication using a self signed ECC certificate.
- Secure password handling with salted sha256 hashes, nonces, and PBKDF2-based at-rest encryption.
- Apache for centralized security configuration and management
- Python Flask for handling:
  - Communication between the web API, and docker container(s) running user supplied scripts
  - Initiation of the shell script that generates docker container and begins running and logging script
