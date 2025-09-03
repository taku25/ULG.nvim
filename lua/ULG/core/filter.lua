-- lua/ULG/core/filter.lua
-- ログのフィルタリングロジックを担当するモジュール

local M = {}

--- フィルター条件に基づいてログ行をフィルタリングする
-- @param lines_to_filter string[] フィルタリング対象の行
-- @param filter_opts table フィルターオプション
--   - category_filters: string[] 表示したいカテゴリのリスト
--   - filter_query: string|nil 絞り込み用の正規表現
--   - filters_enabled: boolean|nil フィルターが有効かどうか
-- @return string[] フィルタリング後の行
function M.apply(lines_to_filter, filter_opts)
  filter_opts = filter_opts or {}
  if not filter_opts.filters_enabled then
    return lines_to_filter
  end

  local lines = lines_to_filter

  -- カテゴリフィルター
  if filter_opts.category_filters and #filter_opts.category_filters > 0 then
    local filtered_by_category = {}
    for _, line in ipairs(lines) do
      for _, category in ipairs(filter_opts.category_filters) do
        if string.find(line, category .. ":", 1, true) then
          table.insert(filtered_by_category, line)
          break
        end
      end
    end
    lines = filtered_by_category
  end

  -- 正規表現フィルター
  if filter_opts.filter_query and filter_opts.filter_query ~= "" then
    local filtered_by_regex = {}
    for _, line in ipairs(lines) do
      if line:match(filter_opts.filter_query) then
        table.insert(filtered_by_regex, line)
      end
    end
    lines = filtered_by_regex
  end

  return lines
end

return M
