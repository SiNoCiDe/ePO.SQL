EXEC EPOCore_DropStoredProc N'EPOPolicy_GetPolicyAssignmentsByProductCode'
GO

-- this is for a branch node only, not a leaf node!
CREATE PROCEDURE [dbo].[EPOPolicy_GetPolicyAssignmentsByProductCode]
(
	@NodeID int,
	@ProductCode nvarchar(128),
	@FeatureID NVARCHAR(128)
)
AS
BEGIN
	SET NOCOUNT ON;

	-- build node table
	DECLARE @tblNodes TABLE(NodeName nvarchar(128), NodeID int, NodeType smallint, PathLength int);
	INSERT INTO @tblNodes
		-- current group
		SELECT TOP 1 BN.NodeName NodeName, @NodeID NodeID, BN.[Type] NodeType, 0 PathLength
		FROM EPOBranchNode BN
		WHERE (BN.AutoID = @NodeID)

		-- all groups above current group through global-root
		UNION SELECT BN.NodeName NodeName, BNE.StartAutoID, BN.[Type], BNE.PathLength
		FROM EPOBranchNode BN INNER JOIN EPOBranchNodeEnum BNE
			ON (BN.AutoID = BNE.StartAutoID)
		WHERE (@NodeID = BNE.EndAutoID);

	-- gather branch nodes below this node
	DECLARE @tblBN TABLE(NodeID int)
	INSERT INTO @tblBN
		SELECT EndAutoID FROM EPOBranchNodeEnum WHERE StartAutoID = @NodeID;
	
	-- build assignment minimal required info, including node name and path from current branch
	SELECT
		PA.AssignmentID,
		PA.PolicyAssignmentID,
		PA.NodeID AS NodeID,
		PA.NodeType AS NodeType,
		PA.PolicyObjectID AS PolicyObjectID,
		PA.SlotID AS SlotID,
		PA.ForceInheritance AS ForceInheritance,
		PA.Hidden AS Hidden,
		PA.TheTimestamp AS TheTimestamp,
		0 AS BrokenInheritanceCount,
		Nodes.NodeName AS NodeName,
		Nodes.PathLength AS PathLength
	INTO #tblAssigned
	FROM EPOPolicyAssignment PA INNER JOIN @tblNodes Nodes
		   ON (PA.NodeID = Nodes.NodeID AND PA.NodeType = Nodes.NodeType);

	-- update our assignments table's BrokenInheritance values to reflect
	--  the number of breaks for a given slot id below us in the tree or
	--  participating leaf nodes.
	UPDATE TA SET TA.BrokenInheritanceCount = TB.N
	FROM #tblAssigned TA INNER JOIN 
	(
		-- adapted from original broken inheritance algorithm for a specific
		--  slot id, this calculates assignment counts per slot id instead.
		SELECT SlotID, COUNT(*) N
		FROM EPOPolicyAssignment PA
		WHERE
		(
			   (  -- child branch nodes
					  PA.NodeType NOT IN (1, 2, 24)
					  AND PA.NodeID IN (SELECT NodeID FROM @tblBN)
			   )
			   OR
			   (  -- leaf nodes
					  PA.NodeType IN (1, 2, 24)
					  AND PA.NodeID IN (
					SELECT AutoID FROM EPOLeafNode
					WHERE (ParentID IN (SELECT NodeID FROM @tblBN UNION SELECT @NodeID)))
			   )
		)
		GROUP BY SlotID
	) TB
	ON TA.SlotID = TB.SlotID;

	-- slot reduction; keep only the assignments, per slot, that are closest to our 
	-- branch node, including direct assignments (pathlength=0).
	DELETE T FROM #tblAssigned T
	INNER JOIN
	(
		SELECT SlotID, MIN(PathLength) MinPath
		FROM #tblAssigned
		GROUP BY SlotID
	) MSP -- min-slot-path
	ON (T.SlotID = MSP.SlotID AND T.PathLength <> MSP.MinPath);

	-- final selection. here we bring in the type info and object-specific stuff
	SELECT 
		PA.*,
		PO.Name,
		PT.FeatureTextID Feature,
		PS.ProductCode [ProductCode],
		PT.CategoryTextID Category,
		PT.TypeTextID [Type],
		PT.TypeID [PolicyTypeID]
	FROM #tblAssigned PA
	INNER JOIN EPOPolicySlot PS ON (PA.SlotID = PS.SlotID)
	INNER JOIN EPOPolicyTypes PT ON (PT.TypeID = PS.TypeID)
	LEFT JOIN EPOPolicyObjects PO ON (PO.PolicyObjectID = PA.PolicyObjectID)
	WHERE
		PT.Hidden = 0
		AND PA.Hidden = 0
		AND (PO.Name IS NULL OR PO.Name NOT LIKE N'__EPO_ENFORCE%')
		AND (@ProductCode = '' OR (PS.ProductCode = @ProductCode))
		AND (@FeatureID IS NULL OR @FeatureID = '' OR (PT.FeatureTextID = @FeatureID))
	ORDER BY SlotID;

	-- no longer needed
	DROP TABLE #tblAssigned;
END
GO