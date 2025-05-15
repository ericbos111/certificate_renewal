# Certificate renewal

## What Is an SSL Certificate, and Why Should You Renew It?
An SSL certificate acts like a digital passport for your website. It verifies the identity of your website and creates a secure connection between your web server and a user’s browser.
This encrypted connection makes sure that any data exchanged between the website and the user, such as login credentials or credit card information, stays confidential and secure.
Most SSL certificates expire after 1 or 2 years, depending on the type of certificate you are using and your certificate authority (CA). Some certificates lapse before that, like Let’s Encrypt, which expires after 90 days.
If you don’t renew your certificates, then users will see a security warning on their web browsers when they visit your site.

![image](https://github.com/user-attachments/assets/562127f1-f263-410a-832d-ac14e7c33680)

## In this exercise we will simulate an application with an expiring certificate.
*	Create a self signed certificate with a validity of 1 day. You can use the documentation for openssl
```
man openssl-req
```

and
  
```
man openssl-x509
```
 	
1. Create a key for the certificate authority
```
 openssl genrsa -des3 -out myCA.key 2048
```
2. Create a certificate authority
```
openssl req -x509 -new -nodes -key myCA.key -sha256 -days 3650 -out myCA.pem
```
3.	Create a key for the application
```
openssl genrsa -out tls.key 2048
```
4.	Create a certificate request
```
openssl req -new -key tls.key -out tls.csr
```
5.	Sign the certificate request with the certificate authority
```
openssl x509 -req -in tls.csr -CA myCA.pem -CAkey myCA.key -CAcreateserial -out tls.crt -days 1 -sha256
```
*	Deploy an application, in your own namespace, that needs a pass-through route using the self signed certificate. The container image, which is accessible at quay.io/redhattraining/todo-angular, has two tags: v1.1, which is the insecure version of the application, and v1.2, which is the secure version. Use the secure version.
```
oc new-project eric
oc new-app quay.io/redhattraining/todo-angular:v1.2
oc create route passthrough todo-angular --service=todo-angular --port 8443
```
* The application does not run, it needs a secret with the certificate. Take a look at the logs of the pod so that you know where to mount the secret.
```
nginx: [emerg] BIO_new_file("/usr/local/etc/ssl/certs/tls.crt") failed (SSL: error:02001002:system library:fopen:No such file or directory:fopen('/usr/local/etc/ssl/certs/tls.crt','r') error:2006D080:BIO routines:BIO_new_file:no such file)
```
*	 You will need to create a secret that contains the certificate and the key, and then mount that secret as a volume.
```
oc create secret tls todo-secret --cert=tls.crt --key=tls.key
oc set volume deployment todo-angular --add --type secret --mount-path /usr/local/etc/ssl/certs --secret-name todo-secret --read-only
```
*	Verify that you can access the application and that the certificate is about to expire
```
oc get route todo-angular
curl -k <route>
openssl s_client -connect <route>:443 -showcerts
```
*	Generate a new certificate with a validity of 90 days
```
openssl req -new -key tls.key -out tls.csr
openssl x509 -req -in tls.csr -CA myCA.pem -CAkey myCA.key -CAcreateserial -out tls.crt -days 90 -sha256
```
* Delete the old secret, create a new secret and delete the pod
```
oc delete secret todo-secret
oc create secret tls todo-secret --cert=tls.crt --key=tls.key
oc delete pod -l deployment=todo-angular
```
*	Verify that you can access the application and that the certificate is valid for another 90 days
```
curl -k <route>
openssl s_client -connect <route>:443 -showcerts
```
