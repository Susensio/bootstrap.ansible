ARG BASE_IMAGE=debian:latest
FROM $BASE_IMAGE

###### SSH ######

# Install OpenSSH server
RUN apt-get update && apt-get install -y openssh-server

# Create SSH directory for the SSH daemon
RUN mkdir -p /var/run/sshd

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Generate the server keys
RUN ssh-keygen -A
RUN chmod 600 /etc/ssh/ssh_host_*


# Expose the SSH port
EXPOSE 22

# Avoid errors on apt install
ARG DEBIAN_FRONTEND=noninteractive

###### USER ######


ARG USERNAME=test
ARG PASSWORD=passwd
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Remove previous user if exists
RUN userdel --remove $(id -nu $USER_UID) || true

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID --create-home $USERNAME

# [Optional] Add sudo support. Omit if you don't need to install software after connecting.
RUN apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME


RUN echo "$USERNAME:$PASSWORD" | chpasswd

RUN chsh -s /bin/bash $USERNAME

USER $USERNAME

###### SSH KEY ######
COPY --chown=$USERNAME .ssh/id_rsa.pub /tmp/id_rsa.pub
RUN mkdir -p /home/$USERNAME/.ssh && \
    cat /tmp/id_rsa.pub >> /home/$USERNAME/.ssh/authorized_keys && \
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh && \
    chmod 700 /home/$USERNAME/.ssh && \
    chmod 600 /home/$USERNAME/.ssh/authorized_keys && \
    rm -f /tmp/id_rsa.pub

# disable password authentication
RUN sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

###### PYTHON and ANSIBLE ######
RUN sudo apt-get update && sudo apt-get install -y python3 ansible

###### LOCALE ######
RUN sudo apt-get update && sudo apt-get install -y locales

RUN sudo sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    sudo locale-gen && \
    sudo dpkg-reconfigure --frontend=noninteractive locales && \
    sudo update-locale LANG=en_US.UTF-8

ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

###### OTHER USUALLY INSTALLED PACKAGES ######
RUN sudo apt-get update && sudo apt-get install -y gettext

# Start the SSH daemon
CMD ["sudo", "/usr/sbin/sshd", "-D"]
