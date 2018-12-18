# Ansible Playbook for Hello User Demo #

This is a demo for showcasing Continuous Integration and delivery or Image
Factory. 

## Prerequisites
- Installing Terraform
- Configuring AWS Credentials
- [Configure Github for CodeDeploy](https://docs.aws.amazon.com/codedeploy/latest/userguide/integrations-partners-github.html)

## Launching Demo
Launching the demo is done in a few steps. We will setup a remote backend for
versioning our infrastructure, allow our instances to launch, show the
health-check with version, update the Ansible playbook with a new version to
pull, push changes, and watch the autoscaling group auto-refresh (rolling
deployment)

### Create your remote backend
A "backend" in Terraform determines how state is loaded and how an operation
such as apply is executed. This abstraction enables non-local file state
storage, remote execution, etc.  By default, Terraform uses the "local"
backend, which is the normal behavior of Terraform you're used to.

Using the default "local" backend is fine for development but you don't want
to check in your state files to version control. The state file can contain
sensitive information that we don't want stored in source control. To
encourage best practices we are not going to check in our state files.
Instead we are going to setup a remote backend that will allow our build
system to persist state without checking in the state files.

In order to use remote state, you should already have an S3 bucket with the
appropriate security controls. If you do not currently have a bucket you will
need to create one. We have provided a terraform module that will allow you to
do this quickly and easily. This module assumes you have an IAM User created
already and is out of scope for this exercise.

For more information: [S3 State Bucket Terraform Module](https://github.com/2ndWatch/tfm_state_bucket)

### Getting the Codebase Ready
If this is your first time giving this demo, you are going to want to create a fork of this repo. If you have never done this before and would like additional instruction on how to fork a repository on GitHub, please read more here - [HowTo: Fork A Repo](https://help.github.com/articles/fork-a-repo/)

We are going to be making some commits and changing version numbers. If demoing live, we want to show that we are comfortable with the tools in this space and git is no exception.  

Once you have forked the codebase, go ahead and create a local copy.

Using SSH:


```bash
$ git clone git@github.com:<username>/ansible_playbook_hellouser.git
```

If you have not setup an SSH key to be used with GitHub, you can use your username and password to clone the repository by using the HTTPS endpoint.

Using HTTPS:

```bash
$ git clone https://github.com/2ndWatch/ansible_playbook_hellouser.git
```



### Launch the CI/CD Pipeline

First navigate to the pipeline plan so you can enable your remote backend using the instructions above if you have never done so before.

```sh
$ cd infra/terraform/pipeline
```

Once you have added your backend, modify variables located in `vars.tf` to work for your demo. This includes modifying:

- bucketname - must be unique
- owner - this should be your github username
- region - (optional) if you wish to show functionality in a different region.

Once those have been updated, proceed with:

```sh
$ terraform init
$ terraform plan
```

If the output of the plan looks good, go ahead an apply.

```sh
$ terraform apply -auto-approve
```

This will initiate a new image build, and if the build is successful, launch the new infrastructure for the application. Subsequent builds 

### Updating version and re-deploy

We can simulate a new applciation release by modifying the version that is deployed via the ansible playbook. The version can be modified in `ansible -> group_vars -> all`.

Acceptable versions are:

- 1.0.0
- 2.0.0

If you wish to demonstrate a failure, you can easily reference any other version number.

Once the version has been updated:

```sh
$ git add .
$ git commit -am 'new release'
$ git push origin master
```



This will trigger a new build. After building the image, the project will then go and deploy a small application stack. Consisting of:

- Application load balancer
- Launch Configuration
- Autoscaling group

All of these resources are set to be launched in the default vpc of the account. The output from the last step is the DNS name of the load balancer.

If you visit the address in a web-browser, you should see some basic information. Likewise if you would like to curl an endpoint to get some information about the app, you can curl the `/health` endpoint for version and maintainer information.

```sh
$ while true; do curl -s <lb_dns_name>/health | jq .Version; sleep 2; done
```

*Note: Make sure you enabled the remote backend on both resources with two different keys. If you did not enable the remote backend, every commit will trigger a new launch of new resources, potentially leading to significant charges.*



