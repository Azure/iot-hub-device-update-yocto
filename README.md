# Building a Custom Linux-based System with Device Update for IotHub Agent using the Yocto Project
> **DISCLAIMER:**  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Introduction

This repository is a tool for experimenting with the integration of Device Update with a Yocto build system. Within this repo there are scripts for helping with builds, a directory structure for supplying keys to the swupdate signing process, and the azurepipelines definitions which can be used for setting up an Azure Dev Ops pipeline for generating the proof of concept image. 

None of the instructions, Azure Pipelines, scripts, or process described here is intended for production use. Do not use this repository as a basis for a production pipeline for integrating images. There are no promises made about the security and stability of the pipeline held within this repository. 

The repository and instructions create an image for the RaspberryPi 4 which can run script and image based updates using Device Update for IoT Hub. It's just to give you a taste of the power and utility of Device Update for IoT Hub.

For more information about the Device Update for IoT Hub, see the link to the source code of [Device Update Agent](https://github.com/Azure/iot-hub-device-update)

## Quick Start

```sh
# Ensure at least 100GB of space for the partition for $HOME (or modify the paths below

git clone git@github.com:azure/iot-hub-device-update-yocto.git --branch scarthgap ~/adu_yocto/iot-hub-device-update-yocto

cd ~/adu_yocto/iot-hub-device-update-yocto

./scripts/install-deps.sh
./scripts/setup.sh

./scripts/build.sh -c -t Debug -o ~/adu_yocto/out

pushd ~/adu_yocto/out
find . -type f -name '*.wic' | grep -i deploy
```


## Prerequisites

Before getting started with this project, please get yourself familiar with the following topics:

- [The Yocto Project Software Overview](https://www.yoctoproject.org/software-overview/)
- [The Device Update for IoTHub Overview](http://github.com/azure/iot-hub-device-update)

### Get Source Code

Please note that, at the time of this writing, we only support `kirkstone` release of the Yocto Project. 

The following variables are referenced in the below section setting up the build. 

| Variable Name | Description |
|---|---|
| $yocto_release | A name of the version of the Yocto Project used to build the images.<br/>(Only support `kirkstone` at the moment) |
| $project_root  | A root directory where this project will be cloned into.|
| $adu_release   | The release of Device Update you're planning on using (should default to `'main'`) | 

You can either just include the string wholesale in the terminal (eg for `$yocto_release` just use `'kirkstone'`) or set the variable at the beginning and then copy the command from this screen.

You can set a bash variable like `yocto_release` like this:

```sh
yocto_release=kirkstone
```
and for `adu_release` like this: 

```sh
adu_release=main
```
and for `project_root` like this:

```sh
project_root=~/
```

The first step for building the project is cloning this repository onto your device using the following command:

1. Clone this repository onto your device:
    
```sh
git clone https://github.com/Azure/iot-hub-device-update-yocto -b <branchname> $project_root/iot-hub-device-update-yocto
```

2. Once you've cloned the project you next need to change into our "working directory" where the individual layers (in Yocto these layers build up to an image like a cake or foundation). 

```sh
cd $project_root/iot-hub-device-update/yocto 
```

3. Once you're in the `yocto` directory we need to check out the Yocto Build "engine" or base layer so we can build with it. 

```sh
git clone --depth 1 --branch $yocto_release git://git.yoctoproject.org/poky
```

4. Next we need to checkout the rest of the dependency layers into the `yocto` directory

    1. Clone the SwUpdate meta layer 

    ```sh
    git clone --depth 1 --branch $yocto_release  https://github.com/sbabic/meta-swupdate
    ```

    2. Clone the Open Embedded meta layer. This layer include many modules (or layers) needed for building a Linux-base system.

    ```sh
    git clone --depth 1 --branch $yocto_release  git://git.openembedded.org/meta-openembedded
    ```

    3. Clone the Raspberry Pi meta layer. Since, the reference image that we are building is for a Raspberry Pi 4 hardware.

    ```sh
    git clone --depth 1 --branch $yocto_release git://git.yoctoproject.org/meta-raspberrypi
    ```

5. Within the same directory we are now going to include the Device Update for IotHub layers which builds Device Update agent and provides those artifacts for the `meta-raspberrypi-adu` layer. The `meta-raspberrypi-adu` layer then integrates the Device Update agent and modifies the image build instructions within `meta-raspberrypi` to output the `adu-base-image-<machine-name>.wic.gz` and `adu-update-image-<machine-name>.swu`. These are artifacts are what is used to test out Device Update for IotHub. For more information on these layers and their outputs please read the `README.md` in each of the repos. 

    1. From within the `yocto` directory checkout `meta-azure-device-update` at the version of Device Update you plan to use in your test. 

    ```sh
    git clone --branch $adu_release http://github.com/azure/meta-azure-device-update
    ```

    2. From within the `yocto` directory checkout `meta-raspberrypi-adu` at the version of Device Update you plan to use in your test. 

    ```sh
    git clone --branch $adu_release http://github.com/azure/meta-raspberrypi-adu
    ```

    3. (optional) If you're planning on using delta updates you can checkout the `meta-iot-hub-device-update-delta` layer that integrates that functionality into that agent. Please read the you can read more [here](https://learn.microsoft.com/azure/iot-hub-device-update/delta-updates) on learn.ms.com and [here](http://github.com/azure/meta-iot-hub-device-update-delta) within the meta-layer repository if you want to know more. 

    ```sh
    git clone --branch $adu_release http://github.com/azure/meta-iot-hub-device-update-delta
    ```

Next we move on to how to build the project assuming you've setup the project like above instructions. If you don't follow the setup instructions you will have to make modifications to `scripts/build.sh` to make sure the build works. 

### Building The Project Locally

#### Install Build Dependencies and Tools

For more information on the Yocto build system, the open embedded base image, and example builds please see [Yocto Project Quick Build](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html#yocto-project-quick-build). 

Please look into `scripts/install-deps.sh` to determine what you may need to integrate into your build as you move forward with the project. 


1. From the `project_root` please execute the following command in your terminal

```sh
sudo ./scripts/install-deps.h
```

### Creating the Private Key for Sw Update Signing

To create the `*.swu` file you will need to provide the build system with a private key and password file so that it can sign the generated image and then create the Sw Update file. This is REQUIRED for a Sw Update update to function. You MUST put the private key and password file inside of the `repo-root-directory/keys` directory. The build will break if you do not complete this step. 

You can find the instructions for generating the private key and creating the password file [here](./keys/README.md). 


### Build The Project

To build the project you can either use our helper script or read the `build.sh` script and use your own terminal  commands to build the layer. Keep in mind Yocto builds can take time depending on your machine. It's best to use a local cache if you're going to be running multiple builds. We use the `-o` option to specify the output directory which in turn builds a local cache that can expedite your local builds. An example invocation is specified below. It is executed from the repositories root folder. NOT the `yocto` directory.

```sh
./scripts/build.sh -c -t Debug -o ~/yocto_build_dir
```

You can use:

```sh
./scripts/build.sh -h
```
to see the list of all options for the build. 

If successful, the output image file (adu-base-image-raspberrypi4-64.wic.gz) and example .swu update file (adu-update-image-raspberrypi4-64.swu) should be located in `$build_output_dir/tmp/deploy/images/raspberrypi4-64` directory. If you built for version 0.0.0.1 you will need to copy the base file out and run the build again to produce a Sw Update update (file ending `.swu`) to be used for the update. You need to do this to make a usable base and update image. 

```sh
.
├── adu-base-image-raspberrypi4-64.wic.gz
├── adu-update-image-raspberrypi4-64.swu
```

## Build Pipelines Status

| Board | Branch | Status |
|---|---|---|
| Raspberry Pi 4 | kirkstone | [![Build Status](https://dev.azure.com/azure-device-update/adu-linux-client/_apis/build/status/azure.iot-hub-device-update-yocto?branchName=honister)](https://dev.azure.com/azure-device-update/adu-linux-client/_build/latest?definitionId=57&branchName=kirkstone)|


## Using Your Own Board and Guidance for Production Images

### Using Your Own Board

If you've tried out Device Update on RaspberryPi 4 and decided you want to try and use it on other hardware you will need to port the `meta-raspberrypi-adu` layer to support your own board. You can find information on what changes may be required [here](https://github.com/Azure/meta-raspberrypi-adu/README.md). Keep in mind the `meta-raspberrypi-adu` layer is provided as is. It's a proof of concept. The repository contains information on how to port the existing proof of concept but you will likely need to add better u-boot scripts, include proper signing key information, and many other small things to get your board up to snuff. These are board dependent and are not under the purview of the Device Update team. If you have a question/comment please make a GitHub issue and we can take a look at it. 


### Recommendations for Adapting for Production Images
Like is said at the beginning of this document this repository is intended to be a proof-of-concept. It is not intended to be a production ready drag and drop solution for building images to be used in the field. Within this repository We've made some recommendations for what might need to be changed but these recommendations should be taken as just that, recommendations. 


## Question? Comment? Bug?

Please create a GitHub issue and we'll get back to you as soon as we're able. Your feedback is integral to improving the agent, our software practices, and product direction. We're always happy to chat.
