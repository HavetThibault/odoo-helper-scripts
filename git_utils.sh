#!/bin/bash

GIT_UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${GIT_UTILS_SCRIPT_DIR}/number_utils.sh"

origin_version_prefix=[0-9]{2}\.0
saas_version_prefix=saas-[0-9]{2}\.[0-9]

get_branch_source() {
    local branch=$1
    if [[ $branch =~ ^${origin_version_prefix}.*$ ]]; then
        echo ${branch%%'-'*}
    elif [[ $branch =~ ^$saas_version_prefix.*$ ]]; then
        local no_saas_branch=${branch#*'-'}
        local version=${no_saas_branch%%'-'*}
        echo saas-$version
    elif [[ $branch =~ ^master.*$ ]]; then
        echo master
    else
        echo "'"$branch"' is not a valid odoo branch name!" 1>&2
        return 1
    fi
}

is_source_branch() {
    local branch=$1
    if [[ $branch =~ ^${origin_version_prefix}$ || $branch =~ ^$saas_version_prefix$ || $branch == "master" ]]; then
        echo 1
    else
        echo 0
    fi
}

get_active_branch() {
    local community=$1
    local enterprise=$2
    if [[ $community == $enterprise ]]; then
        echo $community
        return
    fi
    local is_community_src=$(is_source_branch $community)
    local is_enterprise_src=$(is_source_branch $enterprise)
    if [[ ($is_community_src -eq 1 && $is_enterprise_src -eq 1) ]]; then
        echo "Folder activ branches ($1 and $2) are inconsistent! Please fix that manually!" 1>&2
        return
    elif [[ ($is_community_src -eq 0 && $is_enterprise_src -eq 0) ]]; then
        echo "2 Folder activ branches ($1 and $2) are inconsistent! Please fix that manually!" 1>&2
        return
    elif [[ $is_community_src -eq 0 ]]; then
        echo $community
        return
    fi
    echo $enterprise
}

select_branch() {
    local root_rel_path=$(get_root_relative_path)
    if [[ $root_rel_path == '' ]]; then
        exit 1
    fi
    cd $root_rel_path/odoo

    declare -A availabe_branches
    local community_branch=""
    local enterprise_branch=""
    for branch in $(git branch | sed 's/* /-/g'); do
        if [[ $branch =~ ^-.*$ ]]; then
            community_branch=${branch:1}
            continue
        fi

        if [[ $(is_source_branch $branch) -eq 0 ]]; then
            availabe_branches[$branch]=true
        fi
    done
    cd ../enterprise
    for branch in $(git branch | sed 's/* /-/g'); do
        if [[ $branch =~ ^-.*$ ]]; then
            enterprise_branch=${branch:1}
            continue
        fi

        if [[ $(is_source_branch $branch) -eq 0 ]]; then
            availabe_branches[$branch]=true
        fi
    done

    local active_branch=$(get_active_branch $community_branch $enterprise_branch)
    local i=1
    echo " Please pick a branch"
    for branch in ${!availabe_branches[@]}; do
        if [[ $branch == $active_branch ]]; then
            continue
        fi
        echo "    [$i] $branch"
        branchs[$i]=$branch
        i=$((i+1))
    done

    local valid_answer=0
    while [[ $valid_answer -ne 1 ]]; do
        read answer
        local valid_input=$(is_number $answer)
        if [[ $valid_input -eq 1 ]]; then
            if [[ $answer -ge 1 && $answer -le ${#branchs[@]} ]]; then
                echo "${branchs[$answer]}"
                valid_answer=1
            fi
        fi
        if [[ $valid_answer -ne 1 ]]; then
            echo "Please enter a valid input: 0 < input < $((${#branchs[@]} + 1))"
        fi
    done
}

select_get_branch() {
    local select_output=$(select_branch | tee /dev/tty)
    # Pay attention when displaying select_output, sometimes a '\n' is displayed as a space !
    echo ${select_output##*$'\n'}
}

get_branch_remote() {
    local branch=$1
    local source=$(get_branch_source $branch)

    local exit_status=$?
    if [[ $exit_status -ne 0 ]]; then
        exit $exit_status
    fi

    if [[ $source == $branch ]]; then
        echo "origin"
    else
        echo "dev"
    fi
}

local_branch_exists() {
    local local_branch=$1
    for branch in $(git branch | sed 's/*/ /g'); do
        if [[ $branch == $local_branch ]]; then
            echo 1
            return
        fi
    done
    echo 0
}

remote_branch_exists() {
    local remote=$1
    local branch=$2
    local remote_ls=$(git ls-remote "$remote" "$branch")
    if [[ ${#remote_ls} -eq 0 ]]; then
        echo 0
    else
        echo 1
    fi
}

get_current_branch() {
    local gs_line=$(git status | head -1)
    echo ${gs_line##*' '}
}

changes_exist() {
    if [[ $(git status | tail -1) == "nothing to commit, working tree clean" ]]; then
        echo 0
    else
        echo 1
    fi
}

fetch_if_necessary_switch() {
    local branch=$1
    local remote=$(get_branch_remote $branch)
    if [[ $(local_branch_exists $branch) -eq 0 ]]; then
        git fetch $remote $branch
        if [[ $(get_branch_source $branch) = $branch ]]; then
            git switch -c $branch --track "$remote/$branch"
            return 0
        fi
    fi
    git switch $branch
}

fetch_src_if_necessary() {
    local branch=$1
    local folder=$2
    local branch_src=$(get_branch_source "$branch")
    if [[ $(local_branch_exists "$branch_src") -eq 0 ]]; then
        local has_changes=$(changes_exist)
        if [[ $has_changes -eq 1 ]]; then
            local today=$(date "+%Y-%m-%d==%H:%M:%S")
            local current_branch=$(get_current_branch)
            git stash -m "REBASE==$current_branch==$today"
        fi
        git fetch origin "$branch"
        git switch -c "$branch" --track "origin/$branch" -q
        git switch - -q
        if [[ $has_changes -eq 1 ]]; then
            git stash apply
        fi
    fi
}

local_fetch_if_necessary_switch() {
    local branch_source=$1
    local directory=$2
    if [[ $(local_branch_exists $branch_source) -eq 0 ]]; then
        fetch_src_if_necessary "$branch_source" "$directory"
        add_remote_if_does_not_exists localrepo "$local_repo_folder/$directory"
        git fetch localrepo "$branch_source:$branch_source" -q
    fi
    git switch $branch_source
}

add_remote_if_does_not_exists() {
    local remote_name=$1
    local remote_uri=$2
    if [[ ! $(git remote show | grep -F "$remote_name") ]]; then
        git remote add "$remote_name" "$remote_uri"
    fi
}