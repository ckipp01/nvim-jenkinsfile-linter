local Job = require("plenary.job")
local log = require("plenary.log").new({ plugin = "jenkinsfile-linter", level = "info" })

local user = os.getenv("JENKINS_USER_ID") or os.getenv("JENKINS_USERNAME")
local password = os.getenv("JENKINS_PASSWORD")
local token = os.getenv("JENKINS_API_TOKEN") or os.getenv("JENKINS_TOKEN")
local jenkins_url = os.getenv("JENKINS_URL") or os.getenv("JENKINS_HOST")
local namespace_id = vim.api.nvim_create_namespace("jenkinsfile-linter")
local insecure = os.getenv("JENKINS_INSECURE") and "--insecure" or nil
local validated_msg = "Jenkinsfile successfully validated."
local unauthorized_msg = "ERROR 401 Unauthorized"
local not_found_msg = "ERROR 404 Not Found"

local function reject_nil(tbl)
  return vim.tbl_filter(function(val)
    return val ~= nil
  end, tbl)
end

local function handle_error(msg)
  if msg then
    vim.notify("Something went wrong when trying to validate your file, check the logs.", vim.log.levels.ERROR)
    log.error(msg)
  end
end

local function handle_job_error(job)
  handle_error(table.concat(job:stderr_result(), " "))
end

local function get_crumb_job()
  return Job:new({
    command = "curl",
    args = reject_nil({
      "--silent",
      insecure,
      "--user",
      user .. ":" .. (token or password),
      jenkins_url .. "/crumbIssuer/api/json",
    }),
    on_stderr = handle_error,
  })
end

local validate_job = vim.schedule_wrap(function(crumb_job)
  local concatenated_crumbs = table.concat(crumb_job._stdout_results, " ")
  if string.find(concatenated_crumbs, unauthorized_msg) then
    log.error("Unable to authorize to get breadcrumb. Please check your creds")
  elseif string.find(concatenated_crumbs, not_found_msg) then
    log.error("Unable to hit your crumb provider. Please check your host")
  else
    local args = vim.fn.json_decode(concatenated_crumbs)

    local job = Job:new({
      command = "curl",
      args = reject_nil({
        "--silent",
        insecure,
        "--user",
        user .. ":" .. (token or password),
        "-X",
        "POST",
        "-H",
        "Jenkins-Crumb:" .. args.crumb,
        "-F",
        "jenkinsfile=<" .. vim.fn.expand("%:p"),
        jenkins_url .. "/pipeline-model-converter/validate",
      }),

      on_stderr = handle_error,

      on_stdout = vim.schedule_wrap(function(err, data)
        if err then
          handle_error(err)
          return
        end

        if data == validated_msg then
          vim.diagnostic.reset(namespace_id, 0)
          vim.notify(validated_msg, vim.log.levels.INFO)
        elseif data ~= nil then
          -- better filter out if the line of response is empty,
          -- otherwise throw out unexpected error
          --
          -- We only want to grab the msg, line, and col. We just throw
          -- everything else away. NOTE: That only one seems to ever be
          -- returned so this in theory will only ever match at most once per
          -- call.
          --WorkflowScript: 46: unexpected token: } @ line 46, column 1.
          local msg, line_str, col_str = data:match("WorkflowScript.+%d+: (.+) @ line (%d+), column (%d+).")
          if line_str and col_str then
            local line = tonumber(line_str) - 1
            local col = tonumber(col_str) - 1

            local diag = {
              bufnr = vim.api.nvim_get_current_buf(),
              lnum = line,
              end_lnum = line,
              col = col,
              end_col = col,
              severity = vim.diagnostic.severity.ERROR,
              message = msg,
              source = "jenkinsfile linter",
            }

            vim.diagnostic.set(namespace_id, vim.api.nvim_get_current_buf(), { diag })
          end
        end
      end),
    })
    job:after_failure(handle_job_error)
    job:start()
    return job
  end
end)

local function check_creds()
  if user == nil then
    return false, "JENKINS_USER_ID is not set, please set it"
  elseif password == nil and token == nil then
    return false, "JENKINS_PASSWORD or JENKINS_API_TOKEN need to be set, please set one"
  elseif jenkins_url == nil then
    return false, "JENKINS_URL is not set, please set it"
  else
    return true
  end
end

local function validate()
  local ok, msg = check_creds()
  if ok then
    local job = get_crumb_job()
    job:after_success(validate_job)
    job:after_failure(handle_job_error)
    job:start()
  else
    vim.notify(msg, vim.log.levels.ERROR)
  end
end

return {
  validate = validate,
  check_creds = check_creds,
}
