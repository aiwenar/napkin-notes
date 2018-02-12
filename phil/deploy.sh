Test if I can commit directly to master branch.

#!/bin/sh

# Checkout and deploy a commit, PR (with/without merge to master built in), branch, manifest file, or enqueue a PDF.

# TODO:
# - if any of the fetches error then this should also error
#   - FETCH_HEAD does not exist in this case so `git checkout FETCH_HEAD` returns !0

WHAT=$1
TO_VERB=$2
ENVIRONMENT=$3

function run_ansible_command ()
{
  DEPLOY_COMMAND=$1
  DEPLOY_NOTES=$2
  # --extra-vars "reset_rails_db=true"

  echo "Running ansible-playbook ${DEPLOY_COMMAND}"

  ansible-playbook \
    -i environments/${ENVIRONMENT}/inventory \
    --private-key ~/.ssh/tutor-${ENVIRONMENT}-kp.pem \
    --vault-password-file ~/.vault/${ENVIRONMENT}  \
    --skip-tags configuration \
    --extra-vars="deploy_notes='${DEPLOY_NOTES}'" \
    ${DEPLOY_COMMAND}
}


# If no arguments were specified then print help
if [ -z "${WHAT}" -o '--help' == "${WHAT}" ]
then
  echo "
  Supported Command Syntax
  deploy tutor-js@d34db33f to dev   (deploy a commit)
  deploy tutor-js#123 to dev   (PullRequest with the merge to master)
  deploy tutor-js#123! to dev  (PullRequest without the merge to master)
  deploy tutor-js/branch/name/with/slashes! to dev (branch)
  deploy qa to dev             (makes dev look exactly like qa)
  deploy d34db33f to dev       (applies the manifest)
  deploy 'qa tutor-js#123 exercises/master' to dev (apply multiple repositories)
  deploy enqueue 'col123 col234 col10074' to dev
                 (enqueues PDFs on legacy-textbook-{dev}.cnx.org)
  "
  exit 1
fi


if [ 'enqueue' == "${WHAT}" ]
then
  WHAT=$2
  TO_VERB=$3
  ENVIRONMENT=$4
  for BOOK_ID in ${WHAT}
  do
    # Check if the book ID is correct (starts with 'col' and then only contains numbers)
    # by matching a regular expression and checking that the match is a non-empty string
    if [ -n "$(expr ${BOOK_ID} : '^col\d+$')" ]
    then

      # Tell the server to enqueue
      # curl --progress-bar "http://legacy-textbook-${ENVIRONMENT}.cnx.org/content/${BOOK_ID}/latest/enqueue"
      # from https://superuser.com/questions/272265/getting-curl-to-output-http-status-code
      HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://legacy-textbook-${ENVIRONMENT}.cnx.org/content/${BOOK_ID}/latest/enqueue")
      # If there was an error then print it out
      if [ ${HTTP_STATUS} == 200 ]
      then
        echo "Success: enqueued ${BOOK_ID} on ${ENVIRONMENT}"
      else
        echo "ERROR enqueueing: ${BOOK_ID} HTTP Status was ${HTTP_STATUS}"
      fi
    else
      # It's not a valid book id (does not start with "col")
      echo "ERROR: invalid book id (does it start with 'col'?): ${BOOK_ID}"
    fi
  done
  echo "Done enqueueing ${WHAT} on legacy-textbook-${ENVIRONMENT}"
  exit 0

else
  # workon tutordep

  ANSIBLE_COMMANDS=()
  # These make the links for the deploy message and their lengths must match up
  WHAT_TEXTS=()
  WHAT_URLS=()

  for WHAT_CMD in ${WHAT}
  do

    if [ 'qa' == "${WHAT_CMD}" -o 'prod' == "${WHAT_CMD}" -o 'staging' == "${WHAT_CMD}" -o 'dev' == "${WHAT_CMD}" -o 'latest' == "${WHAT_CMD}" ]
    then

      # Make sure all the repos have the latest commits for manifestly
      ALL_REPOS=$(ls ..)
      for REPO_NAME in ${ALL_REPOS}
      do
        if [ -d "../${REPO_NAME}/.git" ]
        then
          echo "Updating ${REPO_NAME} with new commits from github"
          X=$(cd "../${REPO_NAME}" && git fetch --all)
        fi
      done

      # Deploying from an existing manifest file
      if [ 'prod' == "${WHAT_CMD}" ]
      then
        MANIFEST_HOST='tutor.openstax.org'
      else
        MANIFEST_HOST="tutor-${WHAT_CMD}.openstax.org"
      fi

      MANIFEST_URL="https://${MANIFEST_HOST}/rev.txt"
      echo "Deploying from manifest file on ${MANIFEST_URL}"
      cd .. # manifestly needs to run 1 directory up
      curl --progress ${MANIFEST_URL}
      MANIFEST_ERROR=$(curl --progress ${MANIFEST_URL} | manifestly apply --file /dev/stdin)
      if [ -n "${MANIFEST_ERROR}" ]
      then
        echo ${MANIFEST_ERROR}
        exit 1
      fi
      cd ./tutor-deployment

      WHAT_URL=${MANIFEST_URL}

      # Append to the set of ansible commands that need to run
      ANSIBLE_COMMANDS+=('tutor_web.yml')
      ANSIBLE_COMMANDS+=('accounts_web.yml')
      ANSIBLE_COMMANDS+=('exercises_web.yml')

    elif [ $(expr ${WHAT_CMD} : '^\([a-f0-9]*\)$') ]
    then

      # Make sure all the repos have the latest commits for manifestly
      ALL_REPOS=$(ls ..)
      for REPO_NAME in ${ALL_REPOS}
      do
        if [ -d "../${REPO_NAME}/.git" ]
        then
          echo "Updating ${REPO_NAME} with new commits from github"
          X=$(cd ../${REPO_NAME} && git fetch --all)
        fi
      done

      MANIFEST_SHA=${WHAT_CMD}
      MANIFEST_URL="https://raw.githubusercontent.com/openstax/deploy-manifests/${MANIFEST_SHA}/tutor"

      echo "Deploying from manifest file on ${MANIFEST_URL}"
      cd .. # manifestly needs to run 1 directory up
      curl ${MANIFEST_URL}
      curl ${MANIFEST_URL} | manifestly apply --file /dev/stdin
      echo "Manifestly done"
      cd ./tutor-deployment

      WHAT_URL=${MANIFEST_URL}

      # Append to the set of ansible commands that need to run
      ANSIBLE_COMMANDS+=('tutor_web.yml')
      ANSIBLE_COMMANDS+=('accounts_web.yml')
      ANSIBLE_COMMANDS+=('exercises_web.yml')

    else

      REPO_NAME=$(expr ${WHAT_CMD} : '\([^@#\/]*\)') # Grab the first part of `tutor@d49e32`

      COMMIT_SHA=$(expr ${WHAT_CMD} : '[^@]*@\([a-f0-9]*\)$') # ie `tutor@d49e32`
      PR_NUMBER=$(expr ${WHAT_CMD} : '[^#]*#\([0-9]*\)$')    # ie `tutor#123`
      PR_NUMBER_NOMERGE=$(expr ${WHAT_CMD} : '[^#]*#\([0-9]*\)!$')   # ie `tutor#123!`
      BRANCH=$(expr ${WHAT_CMD} : '[^\/]*\/\(.*\)$')      # ie `tutor/fix/branch/name`

      if [ -z ${REPO_NAME} ]
      then
        echo "Invalid syntax. Must provide a repo name"
        exit 1
      fi

      # TODO: Check if the repo is correct
      cd ../${REPO_NAME}


      if [ "${COMMIT_SHA}" ]
      then
        WHAT_URL="https://github.com/openstax/${REPO_NAME}/commit/${COMMIT_SHA}"

        ## Commit (MUST be the full commit sha)
        echo "${REPO_NAME}: Checking out commit ${COMMIT_SHA}"
        # git fetch origin ${COMMIT_SHA}  || exit 1
        # git checkout FETCH_HEAD         || exit 1

        # ## Commit (partial sha)
        # # (maybe there is a better way to do this?)
        git checkout master          || exit 1
        git pull                     || exit 1
        git checkout ${COMMIT_SHA}   || exit 1

      elif [ "${PR_NUMBER}" ]
      then
        WHAT_URL="https://github.com/openstax/${REPO_NAME}/pull/${PR_NUMBER}"

        ## Pull Request (it should fail with error message if it's not mergeable)
        echo "${REPO_NAME}: Checking out Pull Request ${PR_NUMBER}"
        git fetch origin pull/${PR_NUMBER}/merge  || exit 1
        git checkout FETCH_HEAD                   || exit 1

      elif [ "${PR_NUMBER_NOMERGE}" ]
      then
        WHAT_URL="https://github.com/openstax/${REPO_NAME}/pull/${PR_NUMBER_NOMERGE}"

        ## Pull Request nomerge (for hotfixes)
        echo "${REPO_NAME}: Checking out Pull Request ${PR_NUMBER_NOMERGE} with nomerge"
        git fetch origin pull/${PR_NUMBER_NOMERGE}/head || exit 1
        git checkout FETCH_HEAD                         || exit 1

      elif [ "${BRANCH}" ]
      then
        WHAT_URL="https://github.com/openstax/${REPO_NAME}/tree/${BRANCH}"

        ## Branch
        echo "${REPO_NAME}: Checking out branch ${BRANCH}"
        git fetch origin ${BRANCH}  || exit 1
        git checkout FETCH_HEAD     || exit 1

      else

        echo "Did not understand the command."
        exit 1

      fi

      cd ../tutor-deployment

      if [ 'tutor-js' == "${REPO_NAME}" ]
      then
        DEPLOY_COMMAND='tutor_web.yml'
      elif [ 'tutor-server' == "${REPO_NAME}" ]
      then
        DEPLOY_COMMAND='tutor_web.yml'
      elif [ 'exercises-js' == "${REPO_NAME}" ]
      then
        DEPLOY_COMMAND='exercises_web.yml'
      elif [ 'exercises' == "${REPO_NAME}" ]
      then
        DEPLOY_COMMAND='exercises_web.yml'
      elif [ 'accounts' == "${REPO_NAME}" ]
      then
        DEPLOY_COMMAND='accounts_web.yml'
      elif [ 'tutor-deployment' == "${REPO_NAME}" ]
      then
        # Dummy command, just because I'm lazy and don't want to make appending
        #   ansible commands conditional.
        # But maybe it could be `DEPLOY_COMMAND=''` and then an if test for
        #   appending to the list of ansible commands
        DEPLOY_COMMAND='tutor_web.yml'
      else
        echo "Do not know which deploy command to run for this repo"
        exit 1
      fi

      # Append to the set of ansible commands that need to run
      ANSIBLE_COMMANDS+=(${DEPLOY_COMMAND})

    fi # deploy an environment or a specific repo

    # Append to the list of commands
    WHAT_TEXTS+=(${WHAT_CMD})
    WHAT_URLS+=(${WHAT_URL})

  done # looping over all the repos/envs to check out before deploying


  # If the number of commands is > 1 then just run all of them since there will likely be duplicates
  ANSIBLE_COMMAND_LENGTH=${#ANSIBLE_COMMANDS[@]}

  echo "Deploying to ${ENVIRONMENT}. sleeping for 5sec"
  sleep 5

  # Generate the markdown links for everything that was deployed
  WHAT_LINKS=' '
  WHAT_TEXTS_LENGTH=${#WHAT_TEXTS[@]}
  for (( i=0; i<${WHAT_TEXTS_LENGTH}; i++ ));
  do
    WHAT_URL=${WHAT_URLS[${i}]}
    WHAT_TEXT=${WHAT_TEXTS[${i}]}

    WHAT_LINKS="${WHAT_LINKS} - <${WHAT_URL}|${WHAT_TEXT}>"
  done


  DEPLOY_NOTES=" (@${USER} ran \`deploy ${WHAT} to ${ENVIRONMENT}\`)${WHAT_LINKS}"

  if [ ${ANSIBLE_COMMAND_LENGTH} == 1 ]
  then
    run_ansible_command ${ANSIBLE_COMMANDS[0]} "${DEPLOY_NOTES}"
  else
    # TODO: skip duplicate entries
    run_ansible_command 'accounts_web.yml' "${DEPLOY_NOTES}"
    run_ansible_command 'exercises_web.yml' "${DEPLOY_NOTES}"
    run_ansible_command 'tutor_web.yml' "${DEPLOY_NOTES}"
  fi
fi
