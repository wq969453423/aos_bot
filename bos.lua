-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
nearestEnemy =nearestEnemy or nil

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

--检查两点是否在给定范围内。
--@param x1，y1：第一个点的坐标。
--@param x2，y2：第二个点的坐标。
--@param range：点之间允许的最大距离。
--@return：布尔值，表示点是否在指定范围内。
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- 查找最弱的人
function findWeakestEnemy()
  local weakestPlayer = nil
  local minHealth = math.huge

  for target, state in pairs(LatestGameState.Players) do
      if target ~= ao.id and state.health < minHealth then
          weakestPlayer = state
          minHealth = state.health
      end
  end

  return weakestPlayer
end


function moveAvoid()
    print(colors.red .. "No player in range or insufficient energy. Moving randomly." .. colors.reset)

    local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local randomIndex = math.random(#directionMap)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex]})
end


function moveToEnemy(me)
  if nearestEnemy then
    local dx = nearestEnemy.x - me.x
    local dy = nearestEnemy.y - me.y

    local magnitude = math.sqrt(dx^2 + dy^2)
    dx = dx / magnitude
    dy = dy / magnitude

    local newX = me.x + dx
    local newY = me.y + dy

    if newX >= 0 and newX <= LatestGameState.GameWidth and newY >= 0 and newY <= LatestGameState.GameHeight then
        ao.send({ Target = Game, Action = "Move", Player = ao.id, X = newX, Y = newY })
    end
  end
end


function attackNearestEnemy()
  if not nearestEnemy then
    nearestEnemy = findWeakestEnemy()
  end
  local me = LatestGameState.Players[ao.id]
  local targetInRange = false
  if nearestEnemy and inRange(me.x, me.y, nearestEnemy.x, nearestEnemy.y, 1) then
    targetInRange = true
  end

  if targetInRange and me.energy > 0.3 then
      local attackEnergy = me.energy * 0.5 
      print(colors.red .. "Attacking nearest enemy with energy: " .. attackEnergy .. colors.reset)
      ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(attackEnergy) })
      InAction = false
  elseif targetInRange == false then
    moveToEnemy(me)
    InAction = false
  end
end

function attackWeakestPlayer()
  local me = LatestGameState.Players[ao.id]

  if me.health < 0.3 then
    moveAvoid()
  else
    attackNearestEnemy()
  end

  
end

-- 下一步
function decideNextAction()
  if not InAction then
      InAction = true
      attackWeakestPlayer()
  end
end

-- 用于打印游戏公告和触发游戏状态更新的处理程序。
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true -- InAction logic added
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then -- InAction logic added
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- 触发游戏状态更新的处理程序。
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- 等待期开始时自动确认付款的处理程序。
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- 用于在接收到游戏状态信息时更新游戏状态。
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- 触发决定下一步行动
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false -- InAction logic added
      return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- 当被其他玩家击中时自动攻击的处理程序。
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == undefined then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print(colors.red .. "Returning attack." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
      end
      InAction = false -- InAction logic added
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
