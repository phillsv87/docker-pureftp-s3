# FTPS3
A PureFTP docker image using AWS S3 storage

github - https://github.com/phillsv87/docker-pureftp-s3

FTPS3 is heavily based on https://github.com/stilliard/docker-pure-ftpd

## Environment Variables
- S3_PASSWD_FILE - required - Path S3 bucket password file.
- S3_BUCKET_NAME - required - Name of the S3 Bucket to connect to.
- S3_MOUNT_PATH - location where S3 Bucket will be mounted. default = /home/ftpusers
- S3_USERS_DIR - Parent directory of users created by the ftps3-add-user.sh script. default = /home/ftpusers/ftp
- PURE_PASSWDFILE - User database. default = /home/ftpusers/ftp-config/pureftpd.passwd
- see https://github.com/stilliard/docker-pure-ftpd for additional variables


## Bucket Password File
The Access key ID and Secret access key for the S3 Bucket should have the format below and should
be a single line file
``` txt
<AccessKeyId>:<SecretAccessKey>
```

## Default User
Creating a default user can be done using the FTP_USER_* env vars. Default users will be added 
the user password file store in the S3 bucket. So if this is not preferred do not set a default
user.

## S3 Directory Structure
By default ftps3 will create the following directory structure
``` txt
/home/ftpusers
  |
  +--- ftp-config
  |      |
  |      +--- pureftpd.passwd
  |
  +--- ftp
        |
        +--- <User Name>
        |
        ...
        
```

## Docker Run
``` sh
docker run -d --name ftps3 -p 65121:21 -p 30000-30009:30000-30009 \
    --cap-add SYS_ADMIN --device /dev/fuse \
    -v "$(pwd)/secrets:/s3-secrets" \
    -e "PUBLICHOST=localhost" \
    -e "S3_PASSWD_FILE=/s3-secrets/<Bucket Password File>" \
    -e "S3_BUCKET_NAME=<Bucket Name>" \
    phillsv87/ftps3:1.2
```

## K8s Deployment

``` yaml
apiVersion: v1
kind: Service
metadata:
  name: ftp
  namespace: ftp-stuff
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local
  ports:
  - name: ftp
    port: 21
    targetPort: 21
    protocol: TCP
  - name: port5000
    port: 5000
    targetPort: 5000
    protocol: TCP
  - name: port5001
    port: 5001
    targetPort: 5001
    protocol: TCP
  - name: port5002
    port: 5002
    targetPort: 5002
    protocol: TCP
  - name: port5003
    port: 5003
    targetPort: 5003
    protocol: TCP
  - name: port5004
    port: 5004
    targetPort: 5004
    protocol: TCP
  - name: port5005
    port: 5005
    targetPort: 5005
    protocol: TCP
  - name: port5006
    port: 5006
    targetPort: 5006
    protocol: TCP
  - name: port5007
    port: 5007
    targetPort: 5007
    protocol: TCP
  - name: port5008
    port: 5008
    targetPort: 5008
    protocol: TCP
  - name: port5009
    port: 5009
    targetPort: 5009
    protocol: TCP
  selector:
    app: ftp

---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: ftp
  namespace: ftp-stuff
  labels:
    app: ftp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ftp
  template:
    metadata:
      labels:
        app: ftp
    spec:
      containers:
      - name: ftp
        image: phillsv87/ftps3:1.2
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /s3-secrets
          name: s3-secrets-volume

        env:

        - name: S3_BUCKET_NAME
          value: "<Bucket Name>"
        - name: S3_PASSWD_FILE
          value: "/s3-secrets/<Bucket Password File>"

        - name: PUBLICHOST
          value: "<DNS Name>"

        - name: FTP_PASSIVE_PORTS
          value: "5000:5009"

        # tls flags
        - name: ADDED_FLAGS
          value: "-d -d -j -O clf:/var/log/pureftpd.log --tls 2"
        - name: TLS_CN
          value: "<DNS Name>"
        - name: TLS_ORG
          value: "<Org Name>"
        - name: TLS_C
          value: US

        ports:
        - containerPort: 21
        - containerPort: 5000
        - containerPort: 5001
        - containerPort: 5002
        - containerPort: 5003
        - containerPort: 5004
        - containerPort: 5005
        - containerPort: 5006
        - containerPort: 5007
        - containerPort: 5008
        - containerPort: 5009
      volumes:

      # Password Secret
      - name: s3-secrets-volume
        secret:
          secretName: s3-secrets
```

## Creating Users
Creating new users is done by connecting to the ftp containing and running the ftps3-add-user.sh
script.

``` sh

# Connect to docker container
docker exec -it '<container name>' /bin/bash

# Or connect to k8s container
kubectl exec -it '<pod name>' -- /bin/bash


# You should no be in the containers shell

# make new user
ftps3-add-user.sh '<username>'

```