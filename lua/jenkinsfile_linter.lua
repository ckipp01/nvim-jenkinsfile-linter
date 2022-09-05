local Job = require("plenary.job")
local log = require("plenary.log").new({ plugin = "jenkinsfile-linter", level = "info" })

local user = os.getenv("JENKINS_USER_ID") or os.getenv("JENKINS_USERNAME")
local password = os.getenv("JENKINS_PASSWORD")
local token = os.getenv("JENKINS_API_TOKEN") or os.getenv("JENKINS_TOKEN")
local jenkins_url = os.getenv("JENKINS_URL") or os.getenv("JENKINS_HOST")
local namespace_id = vim.api.nvim_create_namespace("jenkinsfile-linter")
local insecure = os.getenv("JENKINS_INSECURE") and "--insecure" or ""
local validated_msg = "Jenkinsfile successfully validated."
local unauthorized_msg = "ERROR 401 Unauthorized"
local not_found_msg = "ERROR 404 Not Found"

local function get_crumb_job()
  return Job:new({
    command = "curl",
    args = {
      insecure,
      "--user",
      user .. ":" .. (token or password),
      jenkins_url .. "/crumbIssuer/api/json",
    },
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
    local buf_contents = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    return Job
      :new({
        command = "curl",
        args = {
          insecure,
          "--user",
          user .. ":" .. (token or password),
          "-X",
          "POST",
          "-H",
          "Jenkins-Crumb:" .. args.crumb,
          "-d",
          "jenkinsfile=" .. table.concat(buf_contents, "\n"),
          jenkins_url .. "/pipeline-model-converter/validate",
        },

        on_stderr = function(err, _)
          if err then
            log.error(err)
          end
        end,
        on_stdout = vim.schedule_wrap(function(err, data)
          if not err then
            if data == validated_msg then
              vim.diagnostic.reset(namespace_id, 0)
              vim.notify(validated_msg, vim.log.levels.INFO)
            else
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
          else
            vim.notify("Something went wront when trying to valide your file, check the logs.", vim.log.levels.ERROR)
            log.error(err)
          end
        end),
      })
      :start()
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
    get_crumb_job():after(validate_job):start()
  else
    vim.notify(msg, vim.log.levels.ERROR)
  end
end

return {
  validate = validate,
}
