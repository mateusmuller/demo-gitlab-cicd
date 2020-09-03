# demo-webapp

Recently I have started to deal more in dept with Continuous Integration and Continuous Delivery pipelines. During my research, I have noticed this is a complicated subject for those coming from the infrastructure perspective and there are a lot of questions around it.

Due to this reason, I have decided to document this walkthrough to benefit other colleagues around the world too.

Let me give you a brief overview of the project and how all started. Currently I work for a company that mainly supports Java applications running in JBoss/Tomcat and there is a ever growing demand about CI/CD pipelines. Thus, I thought how could I mix the needs of the company with my homelabs, so I decided to create a CI/CD pipeline for Java webapps.

The tools I have used for this project are:

* Apache Maven
* Tomcat
* Sonatype Nexus
* GitLab
* Docker
* Kubernetes (+MetalLB)
* Ansible
* Slack

The Java project was built on top of Java Server Pages and managed by Maven. It was my first experience using it and I wanted to have the developer side feeling and how it brings value to development.

I was running a Docker container with Tomcat with a binding volume to the .WAR file, so every time I run a `mvn package`, the container is already updated.

```
$ docker run -d -p 8888:8080 -v (pwd)/demo-webapp.war:/usr/local/tomcat/webapps/ROOT.war --restart unless-stopped tomcat:latest
```

To improve the environment setup, I have created a docker-compose file and a Ansible playbook to automate the certificate distribution, login on the private registry and some other stuff. The docker-compose crates a Nexus container to be our private registry, GitLab and GitLab runner for the CI/CD and a NGINX reverse proxy to enforce HTTPS in front of the Docker registry (even though it is a Self-signed it is better than nothing).

The flow of the project is:

1. Create a Git repository on GitLab.
2. Push the code to there.
3. The CI/CD pipeline is triggered.
4. The code is compiled, tested and a .war file is generated. The dependencias are cached for the next pipeline execution.
5. The .war file is hold as an artifact used by the Dockerfile to create a new image based on the Tomcat one.
6. The image is pushed to the private registry.
7. The Kubernetes deployment is updated.
8. The application is available through a LoadBalancer service using MetalLB.

## Requirements

The whole landscape is running with containers or VMs with Vagrant and therefore you might need a powerful computer to run.

I am using a XPS 13 with 16GB of RAM and an i7-1065G7. The operating system is a Debian Cinnamon that consumes an average of 3GB.

When I have everything setup, my notebook shows an usage of 15GB of RAM.

Now we will start configuring each application specifically.

## Hosts

The first thing you should do is manually configured the DNS name resolution on /etc/hosts to something like this:

```
192.168.0.107   gitlab.4fasters.com nexus.4fasters.com registry.nexus.4fasters.com
```

From left to right: The IP address of you LAN, the DNS from GitLab dashboard, the DNS from the Nexus dashboard and the DNS from the Docker registry URL.

## Maven

Just to be aware, the maven project was created using a maven extension from vscode with this command:

```
mvn org.apache.maven.plugins:maven-archetype-plugin:3.1.2:generate -DarchetypeArtifactId="maven-archetype-webapp" -DarchetypeGroupId="org.apache.maven.archetypes" -DarchetypeVersion="1.4"
```

## GitLab

Both GitLab and Nexus will be running after starting the docker compose application.

On the root directory run the following command:

```
$ git clone https://github.com/mateusmuller/demo-gitlab-cicd
$ docker-compose up -d
```

Check the URLs below on your browser:

* http://gitlab.4fasters.com:8083/
* http://nexus.4fasters.com:8080/

It will take some time but you should see both!

On the GitLab dashboard, finish the admin account setup and create a new sample project (the user is "root").

You will see a message on the top of the screen asking to add the public key of the ssh keypair used to push the code, so do it. In my situation it is `~/.ssh/id_rsa.pub`.

Once it's done, go to the **admin panel -> Overview -> Runners**. Here you'll see a section called **"Set up a shared Runner manually"** with the URL and access token.

Now you can run a temporary container to register the runner:

```
$ docker run --rm -it -v demo-webapp_gitlab-runner-config:/etc/gitlab-runner gitlab/gitlab-runner:latest register
```

The volume **MUST** be the same name from the one used by the gitlab runner to store the configuration files. Fill the information and everything should work just fine. Just make sure you use the IP address instead of the hostname.

Cool, now we need to manually edit the `config.toml` to modify some parameters. You will find the config file on this location:

```
$ vim /var/lib/docker/volumes/demo-webapp_gitlab-runner-config/_data/config.toml
```

The first one is make sure you use IP address instead of the hostname as the container cannot resolve the GitLab name.

```
url = "http://192.168.0.107:8083/"
clone_url = "http://192.168.0.107:8083/"
```

The second one is ensure the GitLab container can bind to the Docker running on the host:

```
volumes = ["/cache","/var/run/docker.sock:/var/run/docker.sock"]
```

The GitLab is ready to work.

## Nexus

Open the Nexus URL and hit the **"Sign in"** button on the top-right. The credentials should be admin and the password will be inside the docker volume.

```
$ cat /var/lib/docker/volumes/demo-webapp_nexus-data/_data/admin.password
```

After that you can change the password to whatever you want to. I recommend to use only base64 characters so you can hide the password inside the gitlab pipeline.

Once you are logged in, you have to create a Docker repository. Click on the gear button located on the top-left side -> Repositories -> Create repository -> docker(hosted). Fill up a name, check the HTTP port box **"Create an HTTP connector at specified port. Normally used if the server is behind a secure proxy"** and use the port 8082. I would also check the **"Enable Docker V1 API**" box.

Then hit the Create repository button on the bottom. The registry should be up and running.

I am not sure if you noticed but there is a NGINX running and forwarding the requests for the Host "registry.nexus.4fasters.com" to the Nexus container on port 8082 where the docker registry is running. It is using the SSL self-signed certificates inside certs directory. The certificate has a CN=registry.nexus.4fasters.com which means if you change the URL you have to create a fresh certificate with the new CN equals to the URL.

## Kubernetes

I am using [this](https://github.com/janssenlima/kubernetes) project by Janssen Lima to rapidly create a Kubernetes cluster using Vagrant. Obviously, you must have a Oracle Virtual Box and Vagrant properly installed to spin-up the cluster.

By default, the master node is configured with 1GB of RAM and 2 vCPUs while the worker nodes are configured with 512mb and one vCPU. You might change this by manually editing the Vagrantfile like I did.

My master node has 4GB of RAM and 2vCPUs. The worker nodes have 1GB of RAM and 1 vCPU.

After running a `vagrant up` you should have a local Kubernetes cluster with IPs 172.10.10.100, 101 and 102 reachable from the host system.

## Hands on

I suppose you have already cloned this repository, so might copy all the files to a new directory or erase the git configuration, so we can add a new one pointing to your internal gitlab to push the code.

```
$ rm -rf .git/
$ git init
$ git remote add origin ssh://git@gitlab.4fasters.com:2224/root/demo-webapp.git
$ git status
$ git add .
$ git pull origin master --allow-unrelated-histories
$ git commit -m "first version"
$ git push origin master
```

All the code should be on gitlab now and the pipeline should be triggered executing what is describe on .gitlab-ci.yml. We have to change a couple of things.

Go to the gitlab project -> Settings -> CI/CD -> click to Expand the variables section. Create those variables:

- REGISTRY_USER -> admin
- REGISTRY_PASS -> [password that you have set on Nexus]

On REGISTRY_PASS you can click on Mask variable so it won't appear on the pipeline logs. If you trigger the pipeline now, it should work until the deployment stage. Now we need to setup our Kubernetes cluster.

To speed up the configuration we will use the playbook I have created. First of all, go to **ansible/roles/docker-private-registry/vars/main.yaml** and modify the password to the one you are using on Nexus.

Inside the ansible directory you might find some roles I have created to setup different parts of the cluster that requires a manual intervention, so let me describe what each one of them will do:

* docker-private-registry: Distribute the X.509 certificate used on the private registry for SSL, as it is Self-signed we need to manually import it. Modify the /etc/hosts to force DNS name resolution to the private registry. Install pip to install the docker-api afterwards. With the docker-api installed we can control it through ansible to execute the docker login.
* kubernetes-metallb: Setup MetalLB for LoadBalancer service distribution with an allocation pool from 172.10.10.200-172.10.10.210. This is basically a transcription of [this](https://metallb.universe.tf/installation/) page.
* kubernetes-deployment: Deploys our application by creating a separate namespace, deployment with 10 replicas and a service to expose it.
* kubernetes-private-registry: This is the last step to get the .kube/config file from the master node and copy to my laptop. Take care with this. Finally it creates a secret with the private registry credentials so Kubernetes and pull images from Nexus.

To run the playbook just use:

```
$ ansible-playbook -i hosts site.yml
```

Everything should be working. The next step is to add the kubeconfig file as a base64 string to the variables from the pipeline.

Get the file with this command:

```
$ cat ~/.kube/config | base64
```

Go to the gitlab and create a variable for the pipeline (the same way you have done for the docker variables) called K8S_CONFIG and paste this value.

If you trigger the pipeline again it should work just fine.