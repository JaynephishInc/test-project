-- Authored encounters remain visible in Edit; ensure missing ones are rebuilt at server start.
require(game.ServerStorage:WaitForChild("WildBrainrotBuilder")).Ensure()
