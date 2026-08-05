#!/usr/bin/env bash
# shellcheck shell=bash

# Resolve this file's directory portably. This file is sourced by bin/m2d
# (bash), but must also work when the caller's interpreter is zsh, which has no
# BASH_SOURCE; the eval-guarded `%x` is hidden from bash's parser.
if [ -n "${ZSH_VERSION:-}" ]; then
    eval '_m2d_apache_install_self=${(%):-%x}'
else
    _m2d_apache_install_self="${BASH_SOURCE[0]:-$0}"
fi
M2D_APACHE_INSTALL_DIR=$(cd -- "$(dirname -- "$_m2d_apache_install_self")" &> /dev/null && pwd)

function _m2d_install_apache_init_ahut_json ()
{
    local confirm target_file

    target_file="$M2D_APACHE_INSTALL_DIR/../etc/composer/auth.json"

    if [[ -f "$target_file"  ]]; then
        printf '%s' 'You already have auth.json file generated for Magento2Docker. Do you want to keep it (y) or recreate it (n)? [y/n]: ' >&2; read confirm

        if [[ $confirm == 'y' ]]; then
            return 0
        fi

        mv "$target_file" "$target_file.backup"
        echo "The current auth.json file has been archived to: $target_file.backup"
    fi

    if [[ -f ~/.composer/auth.json ]]; then
        printf '%s' 'Do you want to use your auth.json file from the host (~/.composer/auth.json)? [y/n]: ' >&2; read confirm

        if [[ $confirm == 'y' ]]; then
            cp ~/.composer/auth.json "$target_file"
            return 0
        fi
    fi

    echo 'You can use any existing auth.json file or you will be asked to provide public and private composer keys.'
    printf '%s' 'Do you want to use any existing auth.json file? [y/n]: ' >&2; read confirm
    if [[ $confirm == 'y' ]]; then
        local auth_json_path
        while [[ ! -f "$target_file" ]]
        do
            printf '%s' 'Provide a path to auth.json file you want to use: ' >&2; read auth_json_path
            auth_json_path=$(realpath "${auth_json_path/#\~/$HOME}" 2> /dev/null)

            echo "$auth_json_path"

            if [[ -f "$auth_json_path" ]]; then
                cp "$auth_json_path" "$target_file"
                return 0
            fi

            printf '%s' "'$auth_json_path' doesn't exist! Do you want to try again? [y/n]: " >&2; read confirm

            if [[ $confirm == 'n' ]]; then
                break
            fi
        done
    fi

    local username password file_content
    echo 'The auth.json file will be generated based on your public and private keys.'
    printf '%s' 'Provide a public key to repo.magento.com: ' >&2; read username
    printf '%s' 'Provide a private key to repo.magento.com: ' >&2; read password

    file_content=$(cat <<AUTH_JSON
{
    "http-basic": {
        "repo.magento.com": {
            "username": "$username",
            "password": "$password"
        }
    }
}
AUTH_JSON
    )

    echo "$file_content" >> "$target_file"
}

function _m2d_install_apache_init_git_config ()
{
    local confirm target_file

    target_file="$M2D_APACHE_INSTALL_DIR/../etc/git/gitconfig"

    if [[ -f "$target_file"  ]]; then
        printf '%s' 'You already have a git config file created for Magento2Docker. Do you want to keep it? [y/n]: ' >&2; read confirm

        if [[ $confirm == 'y' ]]; then
            return 0
        fi

        mv "$target_file" "$target_file.backup"
        echo "The current git config file has been archived to: $target_file.backup"
    fi

    if [[ -f ~/.gitconfig ]]; then
        printf '%s' 'Do you want to use your current gitconfig file from the host (from ~/.gitconfig)? [y/n]: ' >&2; read confirm

        if [[ $confirm == 'y' ]]; then
            cp ~/.gitconfig "$target_file"
            return 0
        fi
    fi

    local email name file_content
    echo 'Generating minimal git configuration:'
    printf '%s' 'Provide your email address: ' >&2; read email
    printf '%s' 'Provide your full name (name and surname): ' >&2; read name

    file_content=$(cat <<GITCONFIG
[user]
	email = $email
	name = $name

GITCONFIG
    )

    echo "$file_content" >> "$target_file"
}

function _m2d_install_apache_init_certs ()
{
    local confirm
    local target_path="$M2D_APACHE_INSTALL_DIR/../etc/ssh"

    echo 'You may want to add your ssh configuration and keys to the web container, so you will be able to connect to external services like e.g. GithHub'

    if [[ -f ~/.ssh/config ]]; then
        printf '%s' 'Do you want to add SSH config file(s) from the host to the web container? [y/n]: ' >&2; read confirm

        if [[ $confirm == 'y' ]]; then
            cp ~/.ssh/config* "$target_path/"
        fi
    fi

    if [[ -f ~/.ssh/known_hosts ]]; then
        printf '%s' 'Do you want to add known_hosts file from the host to the web container? [y/n]: ' >&2; read confirm

        if [[ $confirm == 'y' ]]; then
            cp ~/.ssh/known_hosts "$target_path/"
        fi
    fi

    printf '%s' 'Do you want to add any of your SSH keys to the web container (you will be able to select which keys to add)? [y/n]: ' >&2; read confirm

    if [[ $confirm == 'n' ]]; then
        return 0
    fi

    for ssh_pub_key in ~/.ssh/*.pub; do
        if [[ "$(basename $ssh_pub_key)" == 'magento2docker.pub' ]]; then
            continue
        fi

        printf '%s' "Add '$ssh_pub_key'? [y/n]: " >&2; read confirm

        if [[ $confirm != 'y' ]]; then
            continue
        fi

        cp "$ssh_pub_key" "$target_path/$(basename $ssh_pub_key)"
        cp "${ssh_pub_key%.pub}" "$target_path/$(basename ${ssh_pub_key%.pub})"
    done
}

_m2d_install_apache_init_ahut_json
_m2d_install_apache_init_git_config
_m2d_install_apache_init_certs
