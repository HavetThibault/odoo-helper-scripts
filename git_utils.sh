#!/bin/bash

GIT_UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${GIT_UTILS_SCRIPT_DIR}/number_utils.sh"
source "${GIT_UTILS_SCRIPT_DIR}/config.sh"

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
    local upgrade=$3
    local stable=''
    local custom=''
    if [[ $(is_source_branch $community) -eq 1 ]]; then
        stable=$community
    else
        custom=$community
    fi

    if [[ $(is_source_branch $enterprise) -eq 1 ]]; then
        if [[ $stable == '' ]]; then
            stable=$enterprise
        else
            if [[ $stable != $enterprise ]]; then
                echo "Enterprise branch doesn't match community branch! Please fix that manually!" 1>&2
                return
            fi
        fi
    else
        if [[ $custom == '' ]]; then
            custom=$enterprise
        else
            if [[ $custom != $enterprise ]]; then
                echo "Enterprise branch doesn't match community branch! Please fix that manually!" 1>&2
                return
            fi
        fi
    fi

    if [[ $upgrade != '' && $upgrade != 'master' ]]; then
        if [[ $custom == '' ]]; then
            custom=$upgrade
        elif [[ $custom != $upgrade ]]; then
            echo "Upgrade branch doesn't match the other branches! Please fix that manually!" 1>&2
            return
        fi
    fi

    if [[ $custom != '' ]]; then
        echo $custom
        return
    fi
    echo $stable
}

get_ws_custom_branches() {
    local -n ws_availabe_branches=$1
    local root_rel_path=$(get_root_relative_path)
    if [[ $root_rel_path == '' ]]; then
        ws_availabe_branches[error]=1
        return
    fi
    cd "$root_rel_path/$community_folder"
    for branch in $(git branch | sed 's/* /-/g'); do
        if [[ $branch =~ ^-.*$ ]]; then
            ws_availabe_branches[community]=${branch:1}
            continue
        fi

        if [[ $(is_source_branch "$branch") -eq 0 ]]; then
            ws_availabe_branches[$branch]=true
        fi
    done
    cd "../$enterprise_folder"
    for branch in $(git branch | sed 's/* /-/g'); do
        if [[ $branch =~ ^-.*$ ]]; then
            ws_availabe_branches[enterprise]=${branch:1}
            continue
        fi

        if [[ $(is_source_branch "$branch") -eq 0 ]]; then
            ws_availabe_branches[$branch]=true
        fi
    done

    if [[ -d "../$upgrade_folder" ]]; then
        cd "../$upgrade_folder"
        for branch in $(git branch | sed 's/* /-/g'); do
            if [[ "$branch" =~ ^-.*$ ]]; then
                ws_availabe_branches[upgrade]=${branch:1}
                continue
            fi

            if [[ "$branch" != 'master' ]]; then
                ws_availabe_branches[$branch]=true
            fi
        done
    fi
    ws_availabe_branches[error]=0
}

select_branch() {
    declare -A availabe_branches
    get_ws_custom_branches availabe_branches
    if [[ ${availabe_branches[error]} -eq 1 ]]; then
        return
    fi
    local community_branch=${availabe_branches['community']}
    local enterprise_branch=${availabe_branches['enterprise']}
    local upgrade_branch=${availabe_branches['upgrade']}
    local active_branch=$(get_active_branch "$community_branch" "$enterprise_branch" "$upgrade_branch")
    local i=1
    echo " Please pick a branch"
    for branch in ${!availabe_branches[@]}; do
        if [[ $branch == $active_branch || $branch == 'community' || $branch == 'enterprise' || $branch == 'upgrade' || $branch == 'error' ]]; then
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
    # local gs_line=$(git status | head -1)
    # echo ${gs_line##*' '}
    git branch --show-current
}

changes_exist() {
    if [[ $(git status | tail -1) == "nothing to commit, working tree clean" ]]; then
        echo 0
    else
        echo 1
    fi
}

fetch_src_if_necessary() {
    local branch=$1
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
        fetch_src_if_necessary "$branch_source"
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