# Private Keys

## Basics

These keys are used by the Yocto build pipeline, specifically the swupdate layer in the meta-raspberrypi-adu layer, to sign the swupdate payload so it can be safely delivered to the device. These keys are test keys. They should not be used in production. Ask your admin/IT group/whoever manages your secrets about scenarios for production keys and how you would manage them.

## How to Generate Test Keys

You're going to be generating two files: a priv.pem file that contains and encoded private key and a priv.pass file that contains the password. First you need to make a file with the first line as your password (e.g. file contents are "microsoft" with an endline) named priv.pass. This is your password file. Second you need to pass the priv.pass file to `openssl genrsa` to generate the private key with your fancy private key file. 

Make sure you have both installed openssl and already created your `priv.pass` file. Next open up your terminal, navigate to the directory with your `priv.pass` file. This should be the `keys` directory within the iot-hub-device-update-yocto if you're going to be using our build system. Then you run this command in your terminal to generate the private key:

```bash 
openssl genrsa -out ./priv.pem -passout file:./priv.pass
```

Congratulations you've now created a password file and used it to create a private key that is now stored in `priv.pem`. The build system can now use it to sign the swupdate payload. 

The public key that is installed into the image during compilation is generated at BUILD time using: 

```shell
openssl rsa -in ${ADUC_PRIVATE_KEY} -passin file:${ADUC_PRIVATE_KEY_PASSWORD} -out public.pem -outform PEM -pubout
```

If the version of OpenSSL on your build machine (meaning the one where you generated the private key) does not match the one on your TARGET machine (meaning the architecture/distro that you are building DeviceUpdate for) you will need to provide a public key statically AND change the `adu-pub-key` directory to include it. You can find more information [here](https://github.com/Azure/meta-azure-device-update/recipes-azure-device-update/adu-pub-key/README.md). 