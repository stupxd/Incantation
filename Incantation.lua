--- STEAMODDED HEADER

--- MOD_NAME: Incantation
--- MOD_ID: incantation
--- MOD_AUTHOR: [jenwalter666, MathIsFun_]
--- MOD_DESCRIPTION: Enables the ability to stack identical consumables.
--- PRIORITY: 0
--- BADGE_COLOR: 000000
--- PREFIX: inc
--- VERSION: 0.0.1b
--- LOADER_VERSION_GEQ: 1.0.0

Incantation = {consumable_in_use = false, accelerate = false} --will port more things over to this global later, but for now it's going to be mostly empty

local MaxStack = 9999
local BulkUseLimit = 9999
local UseStackCap = false
local UseBulkCap = false

local function deepCopy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
  
    local s = seen or {}
    local res = {}
    s[obj] = res
    for k, v in pairs(obj) do res[deepCopy(k, s)] = deepCopy(v, s) end
    return setmetatable(res, getmetatable(obj))
end

local function tablecontains(haystack, needle)
	for k, v in pairs(haystack) do
		if v == needle then
			return true
		end
	end
	return false
end

--this would be so much easier if '[<key>] = true' worked, but clearly something's fucking it up so i have to do this the naive way
local Stackable = {
	'Planet',
	'Tarot',
	'Spectral'
}

local StackableIndividual = {
	'c_black_hole',
	'c_cry_white_hole'
}

local Divisible = {
	'Planet',
	'Tarot',
	'Spectral'
}

local DivisibleIndividual = {
	'c_black_hole',
	'c_cry_white_hole'
}

local BulkUsable = {
	'Planet'
}

local BulkUsableIndividual = {
	'c_black_hole',
	'c_cry_white_hole'
}

--Allow mods to add/remove their own card types to the list

function AllowStacking(set)
	if not tablecontains(Stackable, set) then
		table.insert(Stackable, set)
	end
end

function AllowStackingIndividual(key)
	if not tablecontains(StackableIndividual, key) then
		table.insert(StackableIndividual, key)
	end
end

function AllowDividing(set)
	AllowStacking(set)
	if not tablecontains(Divisible, set) then
		table.insert(Divisible, set)
	end
end

function AllowDividingIndividual(key)
	AllowStackingIndividual(key)
	if not tablecontains(DivisibleIndividual, key) then
		table.insert(DivisibleIndividual, key)
	end
end

function AllowBulkUse(set)
	AllowStacking(set)
	AllowDividing(set)
	if not tablecontains(BulkUsable, set) then
		table.insert(BulkUsable, set)
	end
end

function AllowBulkUseIndividual(key)
	AllowStackingIndividual(key)
	AllowDividingIndividual(key)
	if not tablecontains(BulkUsableIndividual, key) then
		table.insert(BulkUsableIndividual, key)
	end
end

function Card:CanStack()
	return (self.config.center and self.config.center.can_stack) or tablecontains(Stackable, self.ability.set) or tablecontains(StackableIndividual, self.config.center_key)
end

function Card:CanDivide()
	return (self.config.center and self.config.center.can_divide) or tablecontains(Divisible, self.ability.set) or tablecontains(DivisibleIndividual, self.config.center_key)
end

function Card:CanBulkUse()
	return (self.config.center and self.config.center.can_bulk_use) or tablecontains(BulkUsable, self.ability.set) or tablecontains(BulkUsableIndividual, self.config.center_key)
end

function Card:getmaxuse()
	--let modders define their own bulk-use limit in case of concerns with performance
	return (self.config.center.bulk_use_limit or UseBulkCap) and math.min((self.config.center.bulk_use_limit or BulkUseLimit), (self.ability.qty or 1)) or (self.ability.qty or 1)
end

function Card:split(amount, forced)
	if not amount then amount = math.floor((self.ability.qty or 1) / 2) end
	amount = math.max(1, amount)
	if (self.ability.qty or 0) > 1 and (self:CanDivide() or forced) and not self.ignorestacking then
		local traysize = G.consumeables.config.card_limit
		if (self.edition or {}).negative then
			traysize = traysize + 1
		end
		local split = copy_card(self)
		local qty2 = math.min(self.ability.qty - 1, amount)
		G.consumeables.config.card_limit = #G.consumeables.cards + 1
		split.config.ignorestacking = true
		split:add_to_deck()
		G.consumeables:emplace(split)
		split.ability.qty = qty2
		self.ability.qty = self.ability.qty - qty2
		G.consumeables.config.card_limit = traysize
		if qty2 > 1 then
			split:create_stack_display()
		end
		split.created_from_split = true
		split:set_cost()
		self:set_cost()
		play_sound('card1')
		return split
	end
end

function Card:try_merge()
	if self:CanStack() and not self.ignorestacking then
		if not self.edition then self.edition = {} end
		for k, v in pairs(G.consumeables.cards) do
			if not v.edition then v.edition = {} end
			if v ~= self and not v.nomerging and not v.ignorestacking and v.config.center_key == self.config.center_key and ((self.edition.negative and v.edition.negative) or (not self.edition.negative and not v.edition.negative)) and (not UseStackCap or (v.ability.qty or 1) < MaxStack) then
				if not UseStackCap then
					v.ability.qty = (v.ability.qty or 1) + (self.ability.qty or 1)
					v:create_stack_display()
					v:juice_up(0.5, 0.5)
					v:set_cost()
					play_sound('card1')
					self.ignorestacking = true
					self:start_dissolve()
					break
				else
					local space = (UseStackCap and MaxStack or 2^10000) - (v.ability.qty or 1)
					v.ability.qty = (v.ability.qty or 1) + math.min((self.ability.qty or 1), space)
					v:create_stack_display()
					v:juice_up(0.5, 0.5)
					play_sound('card1')
					v:set_cost()
					if (self.ability.qty or 1) - space < 1 then
						self.ignorestacking = true
						self:start_dissolve()
						break
					else
						self.ability.qty = (self.ability.qty or 1) - space
						self:set_cost()
					end
				end
			end
		end
	end
end

local useconsumeref = Card.use_consumeable

function Card:use_consumeable(area, copier)
	local obj = self.config.center
	if obj.bulk_use and type(obj.bulk_use) == 'function' then
		return obj:bulk_use(self, area, copier, self.ability.qty or 1)
	elseif self.ability.consumeable.hand_type then
		update_hand_text({sound = 'button', volume = 0.7, pitch = 0.8, delay = 0.3}, {handname=localize(self.ability.consumeable.hand_type, 'poker_hands'),chips = G.GAME.hands[self.ability.consumeable.hand_type].chips, mult = G.GAME.hands[self.ability.consumeable.hand_type].mult, level=G.GAME.hands[self.ability.consumeable.hand_type].level})
        level_up_hand(copier or self, self.ability.consumeable.hand_type, nil, self.ability.qty or 1)
        update_hand_text({sound = 'button', volume = 0.7, pitch = 1.1, delay = 0}, {mult = 0, chips = 0, handname = '', level = ''})
	elseif self.ability.name == 'Black Hole' then
        update_hand_text({sound = 'button', volume = 0.7, pitch = 0.8, delay = 0.3}, {handname=localize('k_all_hands'),chips = '...', mult = '...', level=''})
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2, func = function()
            play_sound('tarot1')
            self:juice_up(0.8, 0.5)
            G.TAROT_INTERRUPT_PULSE = true
            return true end }))
        update_hand_text({delay = 0}, {mult = '+', StatusText = true})
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.9, func = function()
            play_sound('tarot1')
            self:juice_up(0.8, 0.5)
            return true end }))
        update_hand_text({delay = 0}, {chips = '+', StatusText = true})
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.9, func = function()
            play_sound('tarot1')
            self:juice_up(0.8, 0.5)
            G.TAROT_INTERRUPT_PULSE = nil
            return true end }))
        update_hand_text({sound = 'button', volume = 0.7, pitch = 0.9, delay = 0}, {level='+' .. (self.ability.qty or 1)})
        delay(1.3)
        for k, v in pairs(G.GAME.hands) do
            level_up_hand(self, k, true, self.ability.qty or 1)
        end
        update_hand_text({sound = 'button', volume = 0.7, pitch = 1.1, delay = 0}, {mult = 0, chips = 0, handname = '', level = ''})
	else
		Incantation.accelerate = true
		self.cardinuse = true
		Incantation.consumable_in_use = true
		for i = 1, (self.ability.qty or 1) do
			useconsumeref(self,area,copier)
			G.E_MANAGER:add_event(Event({
				trigger = 'immediate',
				delay = 0.1,
				blockable = true,
				func = function()
					self.ability.qty = (self.ability.qty or 1) - 1
					play_sound('button', self.ability.qty <= 0 and 1 or 0.85, 0.7)
					return true
				end
			}))
		end
		G.E_MANAGER:add_event(Event({
			trigger = 'after',
			delay = 0.1,
			blockable = true,
			func = function()
				Incantation.consumable_in_use = false
				Incantation.accelerate = false
				if obj.keep_on_use and obj:keep_on_use(self) then
					self.ignorestacking = false
					self.ability.qty = 1
				else
					self:start_dissolve()
				end
				return true
			end
		}))
	end
end

local startdissolveref = Card.start_dissolve
function Card:start_dissolve(a,b,c,d)
	if self.ability.qty and self.ability.qty > 1 and Incantation.consumable_in_use then return end
	self.ignorestacking = true
	return startdissolveref(self,a,b,c,d)
end

local usecardref = G.FUNCS.use_card

function CanUseStackButtons()
	if ((G.play and #G.play.cards > 0) or (G.CONTROLLER.locked) or (G.GAME.STOP_USE and G.GAME.STOP_USE > 0)) and G.STATE ~= G.STATES.HAND_PLAYED and G.STATE ~= G.STATES.DRAW_TO_HAND and G.STATE ~= G.STATES.PLAY_TAROT then
		return false
	end
	return true
end

G.FUNCS.use_card = function(e, mute, nosave)
    local card = e.config.ref_table
	local useamount = card.bulkuse and card:getmaxuse() or 1
	if ((card.ability or {}).qty or 1) > useamount then
		card.highlighted = false
		card.bulkuse = false
		local split = card:split(useamount, true)
		e.config.ref_table = split
	end
	usecardref(e, mute, nosave)
end

G.FUNCS.can_split_half = function(e)
	local card = e.config.ref_table
	if (card.ability.qty or 1) > 1 and card.highlighted and CanUseStackButtons() and not card.ignorestacking then
        e.config.colour = G.C.PURPLE
        e.config.button = 'split_half'
		e.states.visible = true
	else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
		e.states.visible = false
	end
end

G.FUNCS.can_split_one = function(e)
	local card = e.config.ref_table
	if (card.ability.qty or 1) > 1 and card.highlighted and CanUseStackButtons() and not card.ignorestacking then
        e.config.colour = G.C.GREEN
        e.config.button = 'split_one'
		e.states.visible = true
	else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
		e.states.visible = false
	end
end

function Card:MergeAvailable()
	for k, v in pairs(G.consumeables.cards) do
		if v then 
			if v ~= self and (v.config or {}).center_key == (self.config or {}).center_key then
				return true
			end
		end
	end
end

G.FUNCS.can_merge_card = function(e)
	local card = e.config.ref_table
	if card:CanStack() and card.highlighted and not card.ignorestacking and CanUseStackButtons() and card:MergeAvailable() then
        e.config.colour = G.C.BLUE
        e.config.button = 'merge_card'
		e.states.visible = true
	else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
		e.states.visible = false
	end
end

G.FUNCS.can_use_all = function(e)
	local card = e.config.ref_table
	if card:CanBulkUse() and (card.ability.qty or 1) > 1 and card.highlighted and CanUseStackButtons() and not card.ignorestacking then
        e.config.colour = G.C.DARK_EDITION
        e.config.button = 'use_all'
		e.states.visible = true
	else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
		e.states.visible = false
	end
end

G.FUNCS.split_half = function(e)
	local card = e.config.ref_table
	card:split(math.floor(card.ability.qty / 2))
end

G.FUNCS.split_one = function(e)
	local card = e.config.ref_table
	card:split(1)
end

G.FUNCS.merge_card = function(e)
	local card = e.config.ref_table
	card:try_merge()
end

G.FUNCS.use_all = function(e)
	local card = e.config.ref_table
	if card:CanBulkUse() and (card.ability.qty or 1) > 1 and card.highlighted then
		card.bulkuse = true
		G.FUNCS.use_card(e, false, true)
	end
end

G.FUNCS.disablestackdisplay = function(e)
	local card = e.config.ref_table
	e.states.visible = ((card.ability.qty or 1) > 1 and not card.ignorestacking) or card.cardinuse
end

function Card:create_stack_display()
	if not self.children.stackdisplay and self:CanStack() then
		self.children.stackdisplay = UIBox {
			definition = {
				n = G.UIT.ROOT,
				config = {
					minh = 0.6,
					maxh = 1.2,
					minw = 0.5,
					maxw = 2,
					r = 0.001,
					padding = 0.1,
					align = 'cm',
					colour = adjust_alpha(darken(G.C.BLACK, 0.2), 0.4),
					shadow = false,
					func = 'disablestackdisplay',
					ref_table = self
				},
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = 'x',
							scale = 0.4,
							colour = G.C.MULT
						}
					},
					{
						n = G.UIT.T,
						config = {
							ref_table = self.ability,
							ref_value = 'qty',
							scale = 0.4,
							colour = G.C.UI.TEXT_LIGHT
						}
					}
				}
			},
			config = {
				align = 'tm',
				bond = 'Strong',
				parent = self
			},
			states = {
				collide = { can = false },
				drag = { can = true }
			}
		}
	end
end

local card_load_ref = Card.load
function Card:load(cardTable, other_card)
	card_load_ref(self, cardTable, other_card)
	if self.ability then
		if self.ability.qty then
			self:create_stack_display()
		end
	end
end

local deckadd = Card.add_to_deck
function Card:add_to_deck(from_debuff)
	deckadd(self, from_debuff)
	if G.consumeables then
		if self:CanStack() then
			if not self.config.ignorestacking then
				G.E_MANAGER:add_event(Event({
					trigger = 'after',
					delay = 0.1,
					blocking = false,
					func = function()
						if self and self.area and self.area ~= 'shop' and self.area ~= 'pack_cards' then
							self:try_merge()
						end
						return true
					end
				}))
			end
			self.config.ignorestacking = nil
		end
	end
end

local hlref = Card.highlight

function Card:highlight(is_highlighted)
	if self:CanStack() and self.added_to_deck and not self.ignorestacking then
		if is_highlighted then
			self.children.splithalfbutton = UIBox {
				definition = {
					n = G.UIT.ROOT,
					config = {
						minh = 0.3,
						maxh = 0.6,
						minw = 0.3,
						maxw = 4,
						r = 0.08,
						padding = 0.1,
						align = 'cm',
						colour = G.C.PURPLE,
						shadow = true,
						button = 'split_half',
						func = 'can_split_half',
						ref_table = self
					},
					nodes = {
						{
							n = G.UIT.T,
							config = {
								text = 'SPLIT HALF',
								scale = 0.3,
								colour = G.C.UI.TEXT_LIGHT
							}
						}
					}
				},
				config = {
					align = 'bmi',
					offset = {
						x = 0,
						y = 0.5
					},
					bond = 'Strong',
					parent = self
				}
			}
			self.children.splitonebutton = UIBox {
				definition = {
					n = G.UIT.ROOT,
					config = {
						minh = 0.3,
						maxh = 0.6,
						minw = 0.3,
						maxw = 4,
						r = 0.08,
						padding = 0.1,
						align = 'cm',
						colour = G.C.GREEN,
						shadow = true,
						button = 'split_one',
						func = 'can_split_one',
						ref_table = self
					},
					nodes = {
						{
							n = G.UIT.T,
							config = {
								text = 'SPLIT ONE',
								scale = 0.3,
								colour = G.C.UI.TEXT_LIGHT
							}
						}
					}
				},
				config = {
					align = 'bmi',
					offset = {
						x = 0,
						y = 1
					},
					bond = 'Strong',
					parent = self
				}
			}
			self.children.mergebutton = UIBox {
				definition = {
					n = G.UIT.ROOT,
					config = {
						minh = 0.3,
						maxh = 0.6,
						minw = 0.3,
						maxw = 4,
						r = 0.08,
						padding = 0.1,
						align = 'cm',
						colour = G.C.BLUE,
						shadow = true,
						button = 'merge_card',
						func = 'can_merge_card',
						ref_table = self
					},
					nodes = {
						{
							n = G.UIT.T,
							config = {
								text = 'MERGE',
								scale = 0.3,
								colour = G.C.UI.TEXT_LIGHT
							}
						}
					}
				},
				config = {
					align = 'bmi',
					offset = {
						x = 0,
						y = 1.5
					},
					bond = 'Strong',
					parent = self
				}
			}
			self.children.useallbutton = UIBox {
				definition = {
					n = G.UIT.ROOT,
					config = {
						minh = 0.3,
						maxh = 0.6,
						minw = 0.3,
						maxw = 4,
						r = 0.08,
						padding = 0.1,
						align = 'cm',
						colour = G.C.DARK_EDITION,
						shadow = true,
						button = 'use_all',
						func = 'can_use_all',
						ref_table = self
					},
					nodes = {
						{
							n = G.UIT.T,
							config = {
								text = 'BULK USE',
								scale = 0.3,
								colour = G.C.UI.TEXT_LIGHT
							}
						}
					}
				},
				config = {
					align = 'bmi',
					offset = {
						x = 0,
						y = 2
					},
					bond = 'Strong',
					parent = self
				}
			}
		else
			if self.children.splithalfbutton then self.children.splithalfbutton:remove();self.children.splithalfbutton = nil end
			if self.children.splitonebutton then self.children.splitonebutton:remove();self.children.splitonebutton = nil end
			if self.children.mergebutton then self.children.mergebutton:remove();self.children.mergebutton = nil end
			if self.children.useallbutton then self.children.useallbutton:remove();self.children.useallbutton = nil end
		end
	end
	return hlref(self,is_highlighted)
end

local costref = Card.set_cost
function Card:set_cost()
	costref(self)
	self.sell_cost = self.sell_cost * ((self.ability or {}).qty or 1)
    self.sell_cost_label = self.facing == 'back' and '?' or self.sell_cost
end

SMODS.Joker:take_ownership('perkeo', {
	name = "Perkeo (Incantation)",
	loc_vars = function(self, info_queue, center)
		info_queue[#info_queue+1] = {key = 'e_negative_consumable', set = 'Edition', config = {extra = 1}}
		return {vars = {center.ability.extra}}
	end,
	calculate = function(self, card, context)
		if context.ending_shop then
			if G.consumeables.cards[1] then
				G.E_MANAGER:add_event(Event({
					func = function() 
						local total, checked, center = 0, 0, nil
						for i = 1, #G.consumeables.cards do
							total = total + (G.consumeables.cards[i].ability.qty or 1)
						end
						local poll = pseudorandom(pseudoseed('perkeo'))*total
						for i = 1, #G.consumeables.cards do
							checked = checked + (G.consumeables.cards[i].ability.qty or 1)
							if checked >= poll then
								center = G.consumeables.cards[i]
								break
							end
						end
						local card = copy_card(center, nil)
						card.ability.qty = 1
						card:set_edition({negative = true}, true)
						card:add_to_deck()
						G.consumeables:emplace(card) 
						return true
					end}))
				card_eval_status_text(context.blueprint_card or card, 'extra', nil, nil, nil, {message = localize('k_duplicated_ex')})
				return {calculated = true}
			end
		end
	end
})
