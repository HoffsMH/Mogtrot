local _, ns = ...

-- Dropping a dragged outfit row or category header: where it would land,
-- the marker that shows it, and the move it makes. Rows start the drag.
local MainWindowDrag = {}

function MainWindowDrag.Attach(Addon, deps, frame)
	local Tree = deps.Tree

	-- Returns where the current drag would land:
	--   { mode = "into", catID }                     drop inside a category
	--   { mode = "outfit", catID, index }            insert an outfit at a position
	--   { mode = "cat", parentID, index }            insert a category at a position
	function Addon:GetDropTarget()
		local drag = self.drag
		if not drag then return end

		local char = MogtrotCharDB
		local _, cursorY = GetCursorPosition()
		cursorY = cursorY / UIParent:GetEffectiveScale()

		-- A row scrolled half out of the list still has real edges, because the ScrollBox
		-- clips it rather than moving it. Without this the cursor could resolve to a row the
		-- user cannot see, and the drop would land somewhere they never pointed at.
		local listTop, listBottom = self.listBox:GetTop(), self.listBox:GetBottom()
		if not listTop or not listBottom then return end
		if cursorY > listTop or cursorY < listBottom then return end

		-- Read from the frames the view currently has realised. Nothing is cached: a
		-- recycling view reassigns frames to different entries as it scrolls.
		return self.listBox:ForEachFrame(function(rowFrame, entry)
			local frameTop, frameBottom = rowFrame:GetTop(), rowFrame:GetBottom()
			if not frameTop or not frameBottom then return end

			-- Hit-test against the visible part, but measure the thirds against the whole
			-- row, so a half-clipped row still splits where its edges really are.
			if cursorY > math.min(frameTop, listTop) or cursorY < math.max(frameBottom, listBottom) then
				return
			end

			local height = frameTop - frameBottom
			local fromTop = frameTop - cursorY

			if entry.kind == "cat" then
				local cat = char.cats[entry.catID]
				if not cat then return end

				if drag.kind == "outfit" then
					-- Anywhere on a header means "put it in this category".
					return { mode = "into", catID = entry.catID, anchor = rowFrame }
				end

				-- Dragging a category: edges reorder, the middle re-parents.
				if fromTop < height * 0.3 then
					local siblings = Tree.SiblingList(char, cat.parent)
					return { mode = "cat", parentID = cat.parent, index = Tree.IndexInList(siblings, entry.catID),
						anchor = rowFrame, edge = "TOP" }
				elseif fromTop > height * 0.7 then
					local siblings = Tree.SiblingList(char, cat.parent)
					return { mode = "cat", parentID = cat.parent, index = (Tree.IndexInList(siblings, entry.catID) or 0) + 1,
						anchor = rowFrame, edge = "BOTTOM" }
				end
				return { mode = "into", catID = entry.catID, anchor = rowFrame }
			end

			-- Over an outfit row.
			if drag.kind == "cat" then
				return { mode = "into", catID = entry.catID, anchor = rowFrame }
			end
			if fromTop < height * 0.5 then
				return { mode = "outfit", catID = entry.catID, index = entry.indexInCat,
					anchor = rowFrame, edge = "TOP" }
			end
			return { mode = "outfit", catID = entry.catID, index = entry.indexInCat + 1,
				anchor = rowFrame, edge = "BOTTOM" }
		end)
	end

	function Addon:FinishDrag()
		local drag = self.drag
		if not drag then return end

		-- Resolve the target before clearing the drag: GetDropTarget needs it.
		local target = self:GetDropTarget()

		self.drag = nil
		frame.InsertMarker:Hide()
		frame.DropInto:Hide()
		if not target then return end

		if drag.kind == "outfit" then
			if target.mode == "into" then
				self:MoveOutfit(drag.outfitID, target.catID)
			elseif target.mode == "outfit" then
				self:MoveOutfit(drag.outfitID, target.catID, target.index)
			end
		else
			if target.mode == "into" then
				self:MoveCategory(drag.catID, target.catID)
			elseif target.mode == "cat" then
				self:MoveCategory(drag.catID, target.parentID, target.index)
			end
		end
	end

	frame:SetScript("OnUpdate", function()
		if not Addon.drag then
			-- Keep the preview up while the mouse is anywhere over either window, so
			-- moving between rows does not flicker it.
			if Addon:PreviewIsShown() and not frame:IsMouseOver() and not Addon:IsPreviewHovered() then
				Addon:HidePreview()
			end
			return
		end

		local target = Addon:GetDropTarget()
		local marker, into = frame.InsertMarker, frame.DropInto

		if not target or not target.anchor then
			marker:Hide()
			into:Hide()
			return
		end

		if target.mode == "into" then
			marker:Hide()
			into:ClearAllPoints()
			into:SetPoint("TOPLEFT", target.anchor, "TOPLEFT", 0, 0)
			into:SetPoint("BOTTOMRIGHT", target.anchor, "BOTTOMRIGHT", 0, 0)
			into:Show()
		else
			into:Hide()
			marker:ClearAllPoints()
			marker:SetPoint("LEFT", target.anchor, "LEFT", 0, 0)
			marker:SetPoint("RIGHT", target.anchor, "RIGHT", 0, 0)
			marker:SetPoint("TOP", target.anchor, target.edge == "TOP" and "TOP" or "BOTTOM", 0, 1)
			marker:Show()
		end
	end)
end

ns.MainWindowDrag = MainWindowDrag
return MainWindowDrag
