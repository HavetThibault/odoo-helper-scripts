#!/bin/bash

is_number() {
    if [[ $1 =~ ^[0-9]+$ ]] ; then
        echo 1
    else
        echo 0
    fi
}
