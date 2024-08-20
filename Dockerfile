FROM debian:testing

# Avoid warnings on apt install
ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NOWARNINGS=yes

###### USER ######
ARG USERNAME=inside
ARG PASSWORD=passwd
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID --create-home $USERNAME

RUN echo "$USERNAME:$PASSWORD" | chpasswd

# Update system
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get autoremove -y && \
    apt-get autoclean -y && \
    apt-get install apt-utils -y

# [Optional] Add sudo support. Omit if you don't need to install software after connecting.
RUN apt-get install -y sudo && \
    echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME

###### LOCALE ######
RUN apt-get install -y locales

RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

###### PYTHON and ANSIBLE ######
RUN sudo apt-get update && sudo apt-get install -y python3 ansible

RUN mkdir /tmp/ansible --mode 777

USER $USERNAME

COPY ./ansible.cfg /ansible/ansible.cfg
# COPY ./bootstrap.yml /ansible/bootstrap.yml
# COPY ./roles /ansible/roles

WORKDIR /ansible

# gather facts
RUN ansible localhost --inventory=localhots, --connection=local --module-name=setup

COPY ./roles/xdg /ansible/roles/xdg
RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=xdg

COPY ./roles/packages /ansible/roles/packages
RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=packages

COPY ./roles/yadm /ansible/roles/yadm
RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=yadm

# COPY ./roles/ssh /ansible/roles/ssh
# RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=ssh

# COPY ./roles/anacron /ansible/roles/anacron
# RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=anacron

# COPY ./roles/bin /ansible/roles/bin
# RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=bin

COPY ./roles/gh /ansible/roles/gh
RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=gh

COPY ./roles/fish /ansible/roles/fish
RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=fish

COPY ./roles/tmux /ansible/roles/tmux
RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=tmux -vvvvv

COPY ./roles/nvim /ansible/roles/nvim
RUN ansible localhost --inventory=localhots, --connection=local --module-name=include_role --args name=nvim

# RUN ansible-playbook --connection=local --inventory=localhost, bootstrap.yml
WORKDIR /home/$USERNAME

# Ensure /etc/profile is loaded
CMD ["bash", "-l", "-c", "exec fish"]
