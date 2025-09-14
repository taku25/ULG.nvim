-- lua/ULG/syntax.lua
-- このファイルはVim scriptから呼び出されることを目的としています。

local M = {}

---
-- Vimのシンタックスファイルから呼び出されるための関数。
-- 設定ファイルからハイライトルールを読み込み、Vim scriptが理解できる形式で返す。
-- @return table A list of tables, e.g., {{hl_group = "ErrorMsg", pattern = ".*Error.*"}, ...}
function M.get_highlight_rules()
  -- pcallで安全に設定を読み込む
  local ok, conf = pcall(require, "UNL.config")
  if not (ok and conf) then return {} end

  local ulg_conf = conf.get("ULG")

  if not (ulg_conf and ulg_conf.highlights and ulg_conf.highlights.enabled and ulg_conf.highlights.groups) then
    return {}
  end

  local rules = {}
  for _, rule in pairs(ulg_conf.highlights.groups) do
    if rule.pattern and rule.hl_group then
      table.insert(rules, {
        hl_group = rule.hl_group,
        pattern = rule.pattern,
      })
    end
  end

  return rules
end

return M
