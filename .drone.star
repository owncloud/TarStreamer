MINIO_MC = "minio/mc:RELEASE.2020-12-18T10-53-53Z"
OC_CI_ALPINE = "owncloudci/alpine:latest"
OC_CI_BAZEL_BUILDIFIER = "owncloudci/bazel-buildifier"
OC_CI_DRONE_SKIP_PIPELINE = "owncloudci/drone-skip-pipeline"
OC_CI_PHP = "owncloudci/php:%s"
PLUGINS_S3 = "plugins/s3"
PLUGINS_S3_CACHE = "plugins/s3-cache:1"
SONARSOURCE_SONAR_SCANNER_CLI = "sonarsource/sonar-scanner-cli"

DEFAULT_PHP_VERSION = "7.4"

# minio mc environment variables
MINIO_MC_ENV = {
    "CACHE_BUCKET": {
        "from_secret": "cache_s3_bucket",
    },
    "MC_HOST": {
        "from_secret": "cache_s3_server",
    },
    "AWS_ACCESS_KEY_ID": {
        "from_secret": "cache_s3_access_key",
    },
    "AWS_SECRET_ACCESS_KEY": {
        "from_secret": "cache_s3_secret_key",
    },
}

dir = {
    "base": "/var/www/owncloud",
}

config = {
    "branches": [
        "master",
    ],
    "codestyle": True,
    "phpstan": True,
    "phan": True,
    "phpunit": {
        "php74": {
            "phpVersions": ["7.4"],
            "coverage": False,
            "extraCommandsBeforeTestRun": [
                "apt update -y",
                "apt-get install php7.4-xdebug -y",
            ],
        },
        "php80": {
            "phpVersions": ["8.0"],
            "coverage": False,
            "extraCommandsBeforeTestRun": [
                "apt update -y",
                "apt-get install php8.0-xdebug -y",
            ],
        },
        "php81": {
            "phpVersions": ["8.1"],
            "coverage": False,
            "extraCommandsBeforeTestRun": [
                "apt update -y",
                "apt-get install php8.1-xdebug -y",
            ],
        },
    },
}

def main(ctx):
    before = beforePipelines(ctx)

    coverageTests = coveragePipelines(ctx)
    if (coverageTests == False):
        print("Errors detected in coveragePipelines. Review messages above.")
        return []

    dependsOn(before, coverageTests)

    nonCoverageTests = nonCoveragePipelines(ctx)
    if (nonCoverageTests == False):
        print("Errors detected in nonCoveragePipelines. Review messages above.")
        return []

    dependsOn(before, nonCoverageTests)

    if (coverageTests == []):
        afterCoverageTests = []
    else:
        afterCoverageTests = afterCoveragePipelines(ctx)
        dependsOn(coverageTests, afterCoverageTests)

    dependsOn(afterCoverageTests + nonCoverageTests)

    return before + coverageTests + afterCoverageTests + nonCoverageTests

def beforePipelines(ctx):
    return codestyle(ctx) + phpstan(ctx) + phan(ctx) + phplint(ctx) + checkStarlark()

def coveragePipelines(ctx):
    # All unit test pipelines that have coverage or other test analysis reported
    phpUnitPipelines = phpTests(ctx, "phpunit", True)
    phpIntegrationPipelines = phpTests(ctx, "phpintegration", True)
    if (phpUnitPipelines == False) or (phpIntegrationPipelines == False):
        return False

    return phpUnitPipelines + phpIntegrationPipelines

def nonCoveragePipelines(ctx):
    # All unit test pipelines that do not have coverage or other test analysis reported
    phpUnitPipelines = phpTests(ctx, "phpunit", False)
    phpIntegrationPipelines = phpTests(ctx, "phpintegration", False)
    if (phpUnitPipelines == False) or (phpIntegrationPipelines == False):
        return False

    return phpUnitPipelines + phpIntegrationPipelines

def afterCoveragePipelines(ctx):
    return [
        sonarAnalysis(ctx),
    ]

def codestyle(ctx):
    pipelines = []

    if "codestyle" not in config:
        return pipelines

    default = {
        "phpVersions": [DEFAULT_PHP_VERSION],
    }

    if "defaults" in config:
        if "codestyle" in config["defaults"]:
            for item in config["defaults"]["codestyle"]:
                default[item] = config["defaults"]["codestyle"][item]

    codestyleConfig = config["codestyle"]

    if type(codestyleConfig) == "bool":
        if codestyleConfig:
            # the config has "codestyle" true, so specify an empty dict that will get the defaults
            codestyleConfig = {}
        else:
            return pipelines

    if len(codestyleConfig) == 0:
        # "codestyle" is an empty dict, so specify a single section that will get the defaults
        codestyleConfig = {"doDefault": {}}

    for category, matrix in codestyleConfig.items():
        params = {}
        for item in default:
            params[item] = matrix[item] if item in matrix else default[item]

        for phpVersion in params["phpVersions"]:
            name = "coding-standard-php%s" % phpVersion

            result = {
                "kind": "pipeline",
                "type": "docker",
                "name": name,
                "workspace": {
                    "base": dir["base"],
                    "path": "server/apps/%s" % ctx.repo.name,
                },
                "steps": skipIfUnchanged(ctx, "lint") +
                         [
                             {
                                 "name": "coding-standard",
                                 "image": OC_CI_PHP % phpVersion,
                                 "commands": [
                                     "make test-php-style",
                                 ],
                             },
                         ],
                "depends_on": [],
                "trigger": {
                    "ref": [
                        "refs/pull/**",
                        "refs/tags/**",
                    ],
                },
            }

            for branch in config["branches"]:
                result["trigger"]["ref"].append("refs/heads/%s" % branch)

            pipelines.append(result)

    return pipelines

def phpstan(ctx):
    pipelines = []

    if "phpstan" not in config:
        return pipelines

    default = {
        "phpVersions": [DEFAULT_PHP_VERSION],
    }

    if "defaults" in config:
        if "phpstan" in config["defaults"]:
            for item in config["defaults"]["phpstan"]:
                default[item] = config["defaults"]["phpstan"][item]

    phpstanConfig = config["phpstan"]

    if type(phpstanConfig) == "bool":
        if phpstanConfig:
            # the config has "phpstan" true, so specify an empty dict that will get the defaults
            phpstanConfig = {}
        else:
            return pipelines

    if len(phpstanConfig) == 0:
        # "phpstan" is an empty dict, so specify a single section that will get the defaults
        phpstanConfig = {"doDefault": {}}

    for category, matrix in phpstanConfig.items():
        params = {}
        for item in default:
            params[item] = matrix[item] if item in matrix else default[item]

        for phpVersion in params["phpVersions"]:
            name = "phpstan-php%s" % phpVersion

            result = {
                "kind": "pipeline",
                "type": "docker",
                "name": name,
                "workspace": {
                    "base": dir["base"],
                    "path": "server/apps/%s" % ctx.repo.name,
                },
                "steps": skipIfUnchanged(ctx, "lint") +
                         [
                             {
                                 "name": "phpstan",
                                 "image": OC_CI_PHP % phpVersion,
                                 "commands": [
                                     "make test-php-phpstan",
                                 ],
                             },
                         ],
                "depends_on": [],
                "trigger": {
                    "ref": [
                        "refs/pull/**",
                        "refs/tags/**",
                    ],
                },
            }

            for branch in config["branches"]:
                result["trigger"]["ref"].append("refs/heads/%s" % branch)

            pipelines.append(result)

    return pipelines

def phan(ctx):
    pipelines = []

    if "phan" not in config:
        return pipelines

    default = {
        "phpVersions": [DEFAULT_PHP_VERSION],
    }

    if "defaults" in config:
        if "phan" in config["defaults"]:
            for item in config["defaults"]["phan"]:
                default[item] = config["defaults"]["phan"][item]

    phanConfig = config["phan"]

    if type(phanConfig) == "bool":
        if phanConfig:
            # the config has "phan" true, so specify an empty dict that will get the defaults
            phanConfig = {}
        else:
            return pipelines

    if len(phanConfig) == 0:
        # "phan" is an empty dict, so specify a single section that will get the defaults
        phanConfig = {"doDefault": {}}

    for category, matrix in phanConfig.items():
        params = {}
        for item in default:
            params[item] = matrix[item] if item in matrix else default[item]

        for phpVersion in params["phpVersions"]:
            name = "phan-php%s" % phpVersion

            result = {
                "kind": "pipeline",
                "type": "docker",
                "name": name,
                "workspace": {
                    "base": dir["base"],
                    "path": "server/apps/%s" % ctx.repo.name,
                },
                "steps": skipIfUnchanged(ctx, "lint") +
                         [
                             {
                                 "name": "phan",
                                 "image": OC_CI_PHP % phpVersion,
                                 "commands": [
                                     "make test-php-phan",
                                 ],
                             },
                         ],
                "depends_on": [],
                "trigger": {
                    "ref": [
                        "refs/pull/**",
                        "refs/tags/**",
                    ],
                },
            }

            for branch in config["branches"]:
                result["trigger"]["ref"].append("refs/heads/%s" % branch)

            pipelines.append(result)

    return pipelines

def phpTests(ctx, testType, withCoverage):
    pipelines = []

    if testType not in config:
        return pipelines

    errorFound = False

    # The default PHP unit test settings for a PR.
    prDefault = {
        "phpVersions": [DEFAULT_PHP_VERSION],
        "coverage": True,
        "includeKeyInMatrixName": False,
        "extraSetup": [],
        "extraEnvironment": {},
        "extraCommandsBeforeTestRun": [],
        "skip": False,
    }

    # The default PHP unit test settings for the cron job (usually runs nightly).
    cronDefault = {
        "phpVersions": [DEFAULT_PHP_VERSION],
        "coverage": True,
        "includeKeyInMatrixName": False,
        "extraSetup": [],
        "extraEnvironment": {},
        "extraCommandsBeforeTestRun": [],
        "skip": False,
    }

    if (ctx.build.event == "cron"):
        default = cronDefault
    else:
        default = prDefault

    if "defaults" in config:
        if testType in config["defaults"]:
            for item in config["defaults"][testType]:
                default[item] = config["defaults"][testType][item]

    phpTestConfig = config[testType]

    if type(phpTestConfig) == "bool":
        if phpTestConfig:
            # the config has just True, so specify an empty dict that will get the defaults
            phpTestConfig = {}
        else:
            return pipelines

    if len(phpTestConfig) == 0:
        # the PHP test config is an empty dict, so specify a single section that will get the defaults
        phpTestConfig = {"doDefault": {}}

    for category, matrix in phpTestConfig.items():
        params = {}
        for item in default:
            params[item] = matrix[item] if item in matrix else default[item]

        if params["skip"]:
            continue

        # if we only want pipelines with coverage, and this pipeline does not do coverage, then do not include it
        if withCoverage and not params["coverage"]:
            continue

        # if we only want pipelines without coverage, and this pipeline does coverage, then do not include it
        if not withCoverage and params["coverage"]:
            continue

        for phpVersion in params["phpVersions"]:
            if testType == "phpunit":
                if params["coverage"]:
                    command = "make test-php-unit-dbg"
                else:
                    command = "make test-php-unit"
            elif params["coverage"]:
                command = "make test-php-integration-dbg"
            else:
                command = "make test-php-integration"

            # Get the first 3 characters of the PHP version (7.4 or 8.0 etc)
            # And use that for constructing the pipeline name
            # That helps shorten pipeline names when using owncloud-ci images
            # that have longer names like 7.4-ubuntu20.04
            phpVersionForPipelineName = phpVersion[0:3]

            keyString = "-" + category if params["includeKeyInMatrixName"] else ""
            name = "%s%s-php%s" % (testType, keyString, phpVersionForPipelineName)
            maxLength = 50
            nameLength = len(name)
            if nameLength > maxLength:
                print("Error: generated phpunit stage name of length", nameLength, "is not supported. The maximum length is " + str(maxLength) + ".", name)
                errorFound = True

            result = {
                "kind": "pipeline",
                "type": "docker",
                "name": name,
                "workspace": {
                    "base": dir["base"],
                    "path": "server/apps/%s" % ctx.repo.name,
                },
                "steps": skipIfUnchanged(ctx, "unit-tests") +
                         params["extraSetup"] +
                         [
                             {
                                 "name": "%s-tests" % testType,
                                 "image": OC_CI_PHP % phpVersion,
                                 "environment": params["extraEnvironment"],
                                 "commands": params["extraCommandsBeforeTestRun"] + [
                                     command,
                                 ],
                             },
                         ],
                "depends_on": [],
                "trigger": {
                    "ref": [
                        "refs/pull/**",
                        "refs/tags/**",
                    ],
                },
            }

            if params["coverage"]:
                result["steps"].append({
                    "name": "coverage-rename",
                    "image": OC_CI_PHP % phpVersion,
                    "commands": [
                        "mv tests/output/clover.xml tests/output/clover-%s.xml" % (name),
                    ],
                })
                result["steps"].append({
                    "name": "coverage-cache-1",
                    "image": PLUGINS_S3,
                    "settings": {
                        "endpoint": {
                            "from_secret": "cache_s3_server",
                        },
                        "bucket": "cache",
                        "source": "tests/output/clover-%s.xml" % (name),
                        "target": "%s/%s" % (ctx.repo.slug, ctx.build.commit + "-${DRONE_BUILD_NUMBER}"),
                        "path_style": True,
                        "strip_prefix": "tests/output",
                        "access_key": {
                            "from_secret": "cache_s3_access_key",
                        },
                        "secret_key": {
                            "from_secret": "cache_s3_secret_key",
                        },
                    },
                })

            for branch in config["branches"]:
                result["trigger"]["ref"].append("refs/heads/%s" % branch)

            pipelines.append(result)

    if errorFound:
        return False

    return pipelines

def sonarAnalysis(ctx, phpVersion = DEFAULT_PHP_VERSION):
    sonar_env = {
        "SONAR_TOKEN": {
            "from_secret": "sonar_token",
        },
        "SONAR_SCANNER_OPTS": "-Xdebug",
    }

    if ctx.build.event == "pull_request":
        sonar_env.update({
            "SONAR_PULL_REQUEST_BASE": "%s" % (ctx.build.target),
            "SONAR_PULL_REQUEST_BRANCH": "%s" % (ctx.build.source),
            "SONAR_PULL_REQUEST_KEY": "%s" % (ctx.build.ref.replace("refs/pull/", "").split("/")[0]),
        })

    repo_slug = ctx.build.source_repo if ctx.build.source_repo else ctx.repo.slug

    result = {
        "kind": "pipeline",
        "type": "docker",
        "name": "sonar-analysis",
        "workspace": {
            "base": dir["base"],
            "path": "server/apps/%s" % ctx.repo.name,
        },
        "clone": {
            "disable": True,  # Sonarcloud does not apply issues on already merged branch
        },
        "steps": [
                     {
                         "name": "clone",
                         "image": OC_CI_ALPINE,
                         "commands": [
                             "git clone https://github.com/%s.git ." % repo_slug,
                             "git checkout $DRONE_COMMIT",
                         ],
                     },
                 ] +
                 skipIfUnchanged(ctx, "unit-tests") +
                 cacheRestore() +
                 composerInstall(phpVersion) +
                 [
                     {
                         "name": "sync-from-cache",
                         "image": MINIO_MC,
                         "environment": MINIO_MC_ENV,
                         "commands": [
                             "mkdir -p results",
                             "mc alias set cache $MC_HOST $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY",
                             "mc mirror cache/cache/%s/%s results/" % (ctx.repo.slug, ctx.build.commit + "-${DRONE_BUILD_NUMBER}"),
                         ],
                     },
                     {
                         "name": "list-coverage-results",
                         "image": OC_CI_PHP % phpVersion,
                         "commands": [
                             "ls -l results",
                         ],
                     },
                     {
                         "name": "sonarcloud",
                         "image": SONARSOURCE_SONAR_SCANNER_CLI,
                         "environment": sonar_env,
                         "when": {
                             "instance": [
                                 "drone.owncloud.services",
                                 "drone.owncloud.com",
                             ],
                         },
                     },
                     {
                         "name": "purge-cache",
                         "image": MINIO_MC,
                         "environment": MINIO_MC_ENV,
                         "commands": [
                             "mc alias set cache $MC_HOST $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY",
                             "mc rm --recursive --force cache/cache/%s/%s" % (ctx.repo.slug, ctx.build.commit + "-${DRONE_BUILD_NUMBER}"),
                         ],
                     },
                 ],
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/heads/master",
                "refs/pull/**",
                "refs/tags/**",
            ],
        },
    }

    for branch in config["branches"]:
        result["trigger"]["ref"].append("refs/heads/%s" % branch)

    return result

def cacheRestore():
    return [{
        "name": "cache-restore",
        "image": PLUGINS_S3_CACHE,
        "settings": {
            "access_key": {
                "from_secret": "cache_s3_access_key",
            },
            "endpoint": {
                "from_secret": "cache_s3_server",
            },
            "restore": True,
            "secret_key": {
                "from_secret": "cache_s3_secret_key",
            },
        },
        "when": {
            "instance": [
                "drone.owncloud.services",
                "drone.owncloud.com",
            ],
        },
    }]

def composerInstall(phpVersion):
    return [{
        "name": "composer-install",
        "image": OC_CI_PHP % phpVersion,
        "environment": {
            "COMPOSER_HOME": "/drone/src/.cache/composer",
        },
        "commands": [
            "make vendor",
        ],
    }]

def dependsOn(earlierStages, nextStages):
    for earlierStage in earlierStages:
        for nextStage in nextStages:
            nextStage["depends_on"].append(earlierStage["name"])

def checkStarlark():
    return [{
        "kind": "pipeline",
        "type": "docker",
        "name": "check-starlark",
        "steps": [
            {
                "name": "format-check-starlark",
                "image": OC_CI_BAZEL_BUILDIFIER,
                "commands": [
                    "buildifier --mode=check .drone.star",
                ],
            },
            {
                "name": "show-diff",
                "image": OC_CI_BAZEL_BUILDIFIER,
                "commands": [
                    "buildifier --mode=fix .drone.star",
                    "git diff",
                ],
                "when": {
                    "status": [
                        "failure",
                    ],
                },
            },
        ],
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/pull/**",
            ],
        },
    }]

def phplint(ctx):
    pipelines = []

    if "phplint" not in config:
        return pipelines

    if type(config["phplint"]) == "bool":
        if not config["phplint"]:
            return pipelines

    result = {
        "kind": "pipeline",
        "type": "docker",
        "name": "lint-test",
        "workspace": {
            "base": dir["base"],
            "path": "server/apps/%s" % ctx.repo.name,
        },
        "steps": skipIfUnchanged(ctx, "lint") +
                 lintTest(),
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/heads/master",
                "refs/tags/**",
                "refs/pull/**",
            ],
        },
    }

    for branch in config["branches"]:
        result["trigger"]["ref"].append("refs/heads/%s" % branch)

    pipelines.append(result)

    return pipelines

def lintTest():
    return [{
        "name": "lint-test",
        "image": OC_CI_PHP % DEFAULT_PHP_VERSION,
        "commands": [
            "make test-lint",
        ],
    }]

def skipIfUnchanged(ctx, type):
    if ("full-ci" in ctx.build.title.lower()):
        return []

    skip_step = {
        "name": "skip-if-unchanged",
        "image": OC_CI_DRONE_SKIP_PIPELINE,
        "when": {
            "event": [
                "pull_request",
            ],
        },
    }

    # these files are not relevant for test pipelines
    # if only files in this array are changed, then don't even run the "lint"
    # pipelines (like code-style, phan, phpstan...)
    allow_skip_if_changed = [
        "^.github/.*",
        "^changelog/.*",
        "^docs/.*",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "LICENSE.md",
        "README.md",
    ]

    if type == "lint":
        skip_step["settings"] = {
            "ALLOW_SKIP_CHANGED": allow_skip_if_changed,
        }
        return [skip_step]

    if type == "unit-tests":
        # if any of these files are touched then run all unit tests
        # note: some oC10 apps have various directories like handlers, rules, etc.
        #       so those are all listed here so that this starlark code can be
        #       the same for every oC10 app.
        unit_files = [
            "^tests/integration/.*",
            "^tests/js/.*",
            "^tests/Unit/.*",
            "^tests/unit/.*",
            "^appinfo/.*",
            "^command/.*",
            "^controller/.*",
            "^css/.*",
            "^db/.*",
            "^handlers/.*",
            "^js/.*",
            "^lib/.*",
            "^rules/.*",
            "^src/.*",
            "^templates/.*",
            "composer.json",
            "composer.lock",
            "Makefile",
            "package.json",
            "package-lock.json",
            "phpunit.xml",
            "yarn.lock",
            "sonar-project.properties",
        ]
        skip_step["settings"] = {
            "DISALLOW_SKIP_CHANGED": unit_files,
        }
        return [skip_step]

    return []
