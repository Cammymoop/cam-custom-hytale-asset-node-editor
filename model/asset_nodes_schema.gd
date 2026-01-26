extends Resource
class_name AssetNodesSchema

@export var value_types: Array[String] = [
    "Density",
    "Curve",
    "CurvePoint",
    "Positions",
    "Material",
    "MaterialProvider",
    "VectorProvider",
    "Terrain",
    "Pattern",
    "Scanner",
    "BlockMask",
    "BlockSubset",
    "Prop",
    "Assignments",
    "EnvironmentProvider",
    "TintProvider",
    "PCNReturnType",
    "PCNDistanceFunction",
    "Point3D",
    "PointGenerator",
    "Stripe",
    "WeightedMaterial",
    "DelimiterFieldFunctionMP",
    "DelimiterDensityPCNReturnType",
    "Runtime",
]

@export var node_types: Dictionary[String, String] = {
    # Density nodes
    "Density|Constant": "ConstantDensity",
    "Density|Sum": "SumDensity",
    "Density|Max": "MaxDensity",
    "Density|Multiplier": "MultiplierDensity",
    "Density|SimplexNoise2D": "SimplexNoise2DDensity",
    "Density|SimplexNoise3D": "SimplexNoise3DDensity",
    "Density|CurveMapper": "CurveMapperDensity",
    "Density|BaseHeight": "BaseHeightDensity",
    "Density|PositionsCellNoise": "PositionsCellNoiseDensity",
    "Density|VectorWarp": "VectorWarpDensity",
    "Density|Anchor": "AnchorDensity",
    "Density|Axis": "AxisDensity",
    "Density|YValue": "YValueDensity",
    "Density|XValue": "XValueDensity",
    "Density|YOverride": "YOverrideDensity",
    "Density|XOverride": "XOverrideDensity",
    "Density|ZOverride": "ZOverrideDensity",
    "Density|Inverter": "InverterDensity",
    "Density|Normalizer": "NormalizerDensity",
    "Density|Imported": "ImportedDensity",
    "Density|Cache": "CacheDensity",
    "Density|Shell": "ShellDensity",
    "Density|Clamp": "ClampDensity",
    "Density|Rotator": "RotatorDensity",
    
    # Curve nodes
    "Curve|Manual": "ManualCurve",
    "Curve|DistanceExponential": "DistanceExponentialCurve",
    "Curve|Constant": "ConstantCurve",
    "Curve|Sum": "SumCurve",
    "Curve|Multiplier": "MultiplierCurve",
    
    # Material Provider nodes
    "MaterialProvider|Constant": "ConstantMaterialProvider",
    "MaterialProvider|Solidity": "SolidityMaterialProvider",
    "MaterialProvider|Queue": "QueueMaterialProvider",
    "MaterialProvider|Striped": "StripedMaterialProvider",
    "MaterialProvider|Weighted": "WeightedMaterialProvider",
    "MaterialProvider|FieldFunction": "FieldFunctionMaterialProvider",
    
    # Positions nodes
    "Positions|Mesh2D": "Mesh2DPositions",
    "Positions|Occurrence": "OccurrencePositions",
    "Positions|Imported": "ImportedPositions",
    "Positions|Offset": "OffsetPositions",
    
    # Pattern nodes
    "Pattern|Floor": "FloorPattern",
    "Pattern|BlockType": "BlockTypePattern",
    "Pattern|BlockSet": "BlockSetPattern",
    "Pattern|Not": "NotPattern",
    
    # Scanner nodes
    "Scanner|ColumnLinear": "ColumnLinearScanner",
    "Scanner|Origin": "OriginScanner",
    
    # Prop nodes
    "Prop|Box": "BoxProp",
    "Prop|Density": "DensityProp",
    
    # Assignments nodes
    "Assignments|Constant": "ConstantAssignments",
    
    # Environment/Tint Provider nodes
    "EnvironmentProvider|Constant": "ConstantEnvironmentProvider",
    "TintProvider|Constant": "ConstantTintProvider",
    
    # PCN ReturnType nodes
    "PCNReturnType|Density": "DensityPCNReturnType",
    "PCNReturnType|CellValue": "CellValuePCNReturnType",
    
    # Single-node value types (no Type field - empty string after |)
    "CurvePoint|": "CurvePoint",
    "Material|": "Material",
    "Point3D|": "Point3D",
    "BlockMask|": "BlockMask",
    "BlockSubset|": "BlockSubset",
    "Stripe|": "Stripe",
    "WeightedMaterial|": "WeightedMaterial",
    "DelimiterFieldFunctionMP|": "DelimiterFieldFunctionMP",
    "DelimiterDensityPCNReturnType|": "DelimiterDensityPCNReturnType",
    
    # PointGenerator nodes
    "PointGenerator|Mesh": "MeshPointGenerator",
    
    # PCNDistanceFunction nodes
    "PCNDistanceFunction|Euclidean": "EuclideanPCNDistanceFunction",
    
    # Terrain nodes
    "Terrain|DAOTerrain": "DAOTerrain",
    
    # Runtime nodes (no Type field)
    "Runtime|": "Runtime",
}

@export var workspace_root_types: Dictionary[String, String] = {
    "HytaleGenerator - Biome": "BiomeRoot",
}

@export var node_schema: Dictionary[String, Dictionary] = {
    "BiomeRoot": {
        "display_name": "[ROOT] Biome",
        "output_value_type": "__ROOT_ONLY",
        "settings": {
            "Name": { "gd_type": TYPE_STRING, "default_value": "" },
        },
        "connections": {
            "Terrain": { "value_type": "Terrain", "multi": false },
            "MaterialProvider": { "value_type": "MaterialProvider", "multi": false },
            "Props": { "value_type": "Runtime", "multi": true },
            "EnvironmentProvider": { "value_type": "EnvironmentProvider", "multi": false },
            "TintProvider": { "value_type": "TintProvider", "multi": false },
        }
    },
    
    # Density nodes
    "ConstantDensity": {
        "display_name": "Constant Density",
        "output_value_type": "Density",
        "settings": {
            "Value": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "ExportAs": { "gd_type": TYPE_STRING, "default_value": "" },
        }
    },
    "SumDensity": {
        "display_name": "Sum Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "ExportAs": { "gd_type": TYPE_STRING, "default_value": "" },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "MaxDensity": {
        "display_name": "Max Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "MultiplierDensity": {
        "display_name": "Multiplier Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "ExportAs": { "gd_type": TYPE_STRING, "default_value": "" },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "SimplexNoise2DDensity": {
        "display_name": "Simplex Noise 2D Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Lacunarity": { "gd_type": TYPE_FLOAT, "default_value": 2.0 },
            "Persistence": { "gd_type": TYPE_FLOAT, "default_value": 0.5 },
            "Octaves": { "gd_type": TYPE_INT, "default_value": 1 },
            "Scale": { "gd_type": TYPE_FLOAT, "default_value": 50.0 },
            "Seed": { "gd_type": TYPE_STRING, "default_value": "A" },
            "ExportAs": { "gd_type": TYPE_STRING, "default_value": "" },
        }
    },
    "SimplexNoise3DDensity": {
        "display_name": "Simplex Noise 3D Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Lacunarity": { "gd_type": TYPE_FLOAT, "default_value": 2.0 },
            "Persistence": { "gd_type": TYPE_FLOAT, "default_value": 0.5 },
            "Octaves": { "gd_type": TYPE_INT, "default_value": 1 },
            "ScaleXZ": { "gd_type": TYPE_FLOAT, "default_value": 50.0 },
            "ScaleY": { "gd_type": TYPE_FLOAT, "default_value": 12.0 },
            "Seed": { "gd_type": TYPE_STRING, "default_value": "A" },
        }
    },
    "CurveMapperDensity": {
        "display_name": "Curve Mapper Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Curve": { "value_type": "Curve", "multi": false },
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "BaseHeightDensity": {
        "display_name": "Base Height Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "BaseHeightName": { "gd_type": TYPE_STRING, "default_value": "Base" },
            "Distance": { "gd_type": TYPE_BOOL, "default_value": true },
        }
    },
    # Positions Cell Noise Density
    "PositionsCellNoiseDensity": {
        "display_name": "Cell Noise Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "MaxDistance": { "gd_type": TYPE_FLOAT, "default_value": 120.0 },
        },
        "connections": {
            "Positions": { "value_type": "Positions", "multi": false },
            "ReturnType": { "value_type": "PCNReturnType", "multi": false },
            "DistanceFunction": { "value_type": "PCNDistanceFunction", "multi": false },
        }
    },
    "VectorWarpDensity": {
        "display_name": "Vector Warp Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "WarpFactor": { "gd_type": TYPE_FLOAT, "default_value": 0.2 },
        },
        "connections": {
            "WarpVector": { "value_type": "Point3D", "multi": false },
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "AnchorDensity": {
        "display_name": "Anchor Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Reversed": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "AxisDensity": {
        "display_name": "Axis Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "IsAnchored": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Axis": { "value_type": "Point3D", "multi": false },
            "Curve": { "value_type": "Curve", "multi": false },
        }
    },
    "YValueDensity": {
        "display_name": "Y Value Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        }
    },
    "XValueDensity": {
        "display_name": "X Value Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        }
    },
    "YOverrideDensity": {
        "display_name": "Y Override Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Value": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "XOverrideDensity": {
        "display_name": "X Override Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Value": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "ZOverrideDensity": {
        "display_name": "Z Override Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Value": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "InverterDensity": {
        "display_name": "Inverter Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "NormalizerDensity": {
        "display_name": "Normalizer Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "FromMin": { "gd_type": TYPE_FLOAT, "default_value": -1.0 },
            "FromMax": { "gd_type": TYPE_FLOAT, "default_value": 1.0 },
            "ToMin": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "ToMax": { "gd_type": TYPE_FLOAT, "default_value": 1.0 },
            "ExportAs": { "gd_type": TYPE_STRING, "default_value": "" },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "ImportedDensity": {
        "display_name": "Imported Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Name": { "gd_type": TYPE_STRING, "default_value": "" },
        }
    },
    "CacheDensity": {
        "display_name": "Cache Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "ExportAs": { "gd_type": TYPE_STRING, "default_value": "" },
            "Capacity": { "gd_type": TYPE_INT, "default_value": 3 },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "ShellDensity": {
        "display_name": "Shell Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Mirror": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Axis": { "value_type": "Point3D", "multi": false },
            "AngleCurve": { "value_type": "Curve", "multi": false },
            "DistanceCurve": { "value_type": "Curve", "multi": false },
        }
    },
    "ClampDensity": {
        "display_name": "Clamp Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "WallA": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "WallB": { "gd_type": TYPE_FLOAT, "default_value": 1.0 },
        },
        "connections": {
            "Inputs": { "value_type": "Density", "multi": true },
        }
    },
    "RotatorDensity": {
        "display_name": "Rotator Density",
        "output_value_type": "Density",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "SpinAngle": { "gd_type": TYPE_FLOAT, "default_value": 180.0 },
        },
        "connections": {
            "NewYAxis": { "value_type": "Point3D", "multi": false },
        }
    },
    
    # CurvePoint (single-node value type)
    "CurvePoint": {
        "display_name": "Curve Point",
        "output_value_type": "CurvePoint",
        "settings": {
            "In": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "Out": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        }
    },
    
    # Curve nodes
    "ManualCurve": {
        "display_name": "Manual Curve",
        "output_value_type": "Curve",
        "connections": {
            "Points": { "value_type": "CurvePoint", "multi": true },
        }
    },
    "DistanceExponentialCurve": {
        "display_name": "Distance Exponential Curve",
        "output_value_type": "Curve",
        "settings": {
            "Exponent": { "gd_type": TYPE_FLOAT, "default_value": 1.0 },
            "Range": { "gd_type": TYPE_FLOAT, "default_value": 6.0 },
        }
    },
    "ConstantCurve": {
        "display_name": "Constant Curve",
        "output_value_type": "Curve",
        "settings": {
            "Value": { "gd_type": TYPE_FLOAT, "default_value": 1.0 },
        }
    },
    "SumCurve": {
        "display_name": "Sum Curve",
        "output_value_type": "Curve",
        "connections": {
            "Curves": { "value_type": "Curve", "multi": true },
        }
    },
    "MultiplierCurve": {
        "display_name": "Multiplier Curve",
        "output_value_type": "Curve",
        "connections": {
            "Curves": { "value_type": "Curve", "multi": true },
        }
    },
    
    # Material (single-node value type)
    "Material": {
        "display_name": "Material",
        "output_value_type": "Material",
        "settings": {
            "Solid": { "gd_type": TYPE_STRING, "default_value": "" },
        }
    },
    
    # Material Provider nodes
    "ConstantMaterialProvider": {
        "display_name": "Constant Material Provider",
        "output_value_type": "MaterialProvider",
        "connections": {
            "Material": { "value_type": "Material", "multi": false },
        }
    },
    "SolidityMaterialProvider": {
        "display_name": "Solidity Material Provider",
        "output_value_type": "MaterialProvider",
        "connections": {
            "Solid": { "value_type": "MaterialProvider", "multi": false },
            "Empty": { "value_type": "MaterialProvider", "multi": false },
        }
    },
    "QueueMaterialProvider": {
        "display_name": "Queue Material Provider",
        "output_value_type": "MaterialProvider",
        "connections": {
            "Queue": { "value_type": "MaterialProvider", "multi": true },
        }
    },
    "StripedMaterialProvider": {
        "display_name": "Striped Material Provider",
        "output_value_type": "MaterialProvider",
        "connections": {
            "Material": { "value_type": "MaterialProvider", "multi": false },
            "Stripes": { "value_type": "Stripe", "multi": true },
        }
    },
    "WeightedMaterialProvider": {
        "display_name": "Weighted Material Provider",
        "output_value_type": "MaterialProvider",
        "settings": {
            "Seed": { "gd_type": TYPE_STRING, "default_value": "A" },
            "SkipChance": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        },
        "connections": {
            "WeightedMaterials": { "value_type": "WeightedMaterial", "multi": true },
        }
    },
    "FieldFunctionMaterialProvider": {
        "display_name": "Field Function Material Provider",
        "output_value_type": "MaterialProvider",
        "connections": {
            "FieldFunction": { "value_type": "Density", "multi": false },
            "Delimiters": { "value_type": "DelimiterFieldFunctionMP", "multi": true },
        }
    },
    
    # Point3D (single-node value type)
    "Point3D": {
        "display_name": "Point 3D",
        "output_value_type": "Point3D",
        "settings": {
            "X": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "Y": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "Z": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        }
    },
    
    # PointGenerator nodes
    "MeshPointGenerator": {
        "display_name": "Mesh Point Generator",
        "output_value_type": "PointGenerator",
        "settings": {
            "Type": { "gd_type": TYPE_STRING, "default_value": "Mesh" },
            "Jitter": { "gd_type": TYPE_FLOAT, "default_value": 0.25 },
            "ScaleX": { "gd_type": TYPE_FLOAT, "default_value": 20.0 },
            "ScaleY": { "gd_type": TYPE_FLOAT, "default_value": 40.0 },
            "ScaleZ": { "gd_type": TYPE_FLOAT, "default_value": 20.0 },
            "Seed": { "gd_type": TYPE_STRING, "default_value": "A" },
        }
    },
    
    # Positions nodes
    "Mesh2DPositions": {
        "display_name": "Mesh 2D Positions",
        "output_value_type": "Positions",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "PointsY": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        },
        "connections": {
            "PointGenerator": { "value_type": "PointGenerator", "multi": false },
        }
    },
    "OccurrencePositions": {
        "display_name": "Occurrence Positions",
        "output_value_type": "Positions",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Seed": { "gd_type": TYPE_STRING, "default_value": "A" },
            "ExportAs": { "gd_type": TYPE_STRING, "default_value": "" },
        },
        "connections": {
            "FieldFunction": { "value_type": "Density", "multi": false },
            "Positions": { "value_type": "Positions", "multi": false },
        }
    },
    "ImportedPositions": {
        "display_name": "Imported Positions",
        "output_value_type": "Positions",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Name": { "gd_type": TYPE_STRING, "default_value": "" },
        }
    },
    "OffsetPositions": {
        "display_name": "Offset Positions",
        "output_value_type": "Positions",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "OffsetX": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "OffsetY": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "OffsetZ": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "ExportAs": { "gd_type": TYPE_STRING, "default_value": "" },
        },
        "connections": {
            "Positions": { "value_type": "Positions", "multi": false },
        }
    },
    
    # BlockSubset (single-node value type)
    "BlockSubset": {
        "display_name": "Block Subset",
        "output_value_type": "BlockSubset",
        "settings": {
            "Inclusive": { "gd_type": TYPE_BOOL, "default_value": true },
        },
        "connections": {
            "Materials": { "value_type": "Material", "multi": true },
        }
    },
    
    # BlockMask (single-node value type)
    "BlockMask": {
        "display_name": "Block Mask",
        "output_value_type": "BlockMask",
        "connections": {
            "DontPlace": { "value_type": "BlockSubset", "multi": false },
        }
    },
    
    # Pattern nodes
    "FloorPattern": {
        "display_name": "Floor Pattern",
        "output_value_type": "Pattern",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Origin": { "value_type": "Pattern", "multi": false },
            "Floor": { "value_type": "Pattern", "multi": false },
        }
    },
    "BlockTypePattern": {
        "display_name": "Block Type Pattern",
        "output_value_type": "Pattern",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Material": { "value_type": "Material", "multi": false },
        }
    },
    "BlockSetPattern": {
        "display_name": "Block Set Pattern",
        "output_value_type": "Pattern",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "BlockSet": { "value_type": "BlockSubset", "multi": false },
        }
    },
    "NotPattern": {
        "display_name": "Not Pattern",
        "output_value_type": "Pattern",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Pattern": { "value_type": "Pattern", "multi": false },
        }
    },
    
    # Stripe (single-node value type)
    "Stripe": {
        "display_name": "Stripe",
        "output_value_type": "Stripe",
        "settings": {
            "TopY": { "gd_type": TYPE_INT, "default_value": 0 },
            "BottomY": { "gd_type": TYPE_INT, "default_value": 0 },
        }
    },
    
    # WeightedMaterial (single-node value type)
    "WeightedMaterial": {
        "display_name": "Weighted Material",
        "output_value_type": "WeightedMaterial",
        "settings": {
            "Weight": { "gd_type": TYPE_FLOAT, "default_value": 1.0 },
        },
        "connections": {
            "Material": { "value_type": "MaterialProvider", "multi": false },
        }
    },
    
    # DelimiterFieldFunctionMP (single-node value type)
    "DelimiterFieldFunctionMP": {
        "display_name": "Delimiter (Field Function MP)",
        "output_value_type": "DelimiterFieldFunctionMP",
        "settings": {
            "From": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
            "To": { "gd_type": TYPE_FLOAT, "default_value": 1.0 },
        },
        "connections": {
            "Material": { "value_type": "MaterialProvider", "multi": false },
        }
    },
    
    # Delimiter for Positions Cell Noise Density Return Type (single-node value type)
    "DelimiterDensityPCNReturnType": {
        "display_name": "Delimiter (Density Cell Noise Return Type)",
        "output_value_type": "DelimiterDensityPCNReturnType",
        "settings": {
            "From": { "gd_type": TYPE_FLOAT, "default_value": -1.0 },
            "To": { "gd_type": TYPE_FLOAT, "default_value": 1.0 },
        },
        "connections": {
            "Density": { "value_type": "Density", "multi": false },
        }
    },
    
    # Scanner nodes
    "ColumnLinearScanner": {
        "display_name": "Column Linear Scanner",
        "output_value_type": "Scanner",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "MaxY": { "gd_type": TYPE_INT, "default_value": 320 },
            "MinY": { "gd_type": TYPE_INT, "default_value": 0 },
            "RelativeToPosition": { "gd_type": TYPE_BOOL, "default_value": false },
            "BaseHeightName": { "gd_type": TYPE_STRING, "default_value": "Base" },
            "TopDownOrder": { "gd_type": TYPE_BOOL, "default_value": true },
            "ResultCap": { "gd_type": TYPE_INT, "default_value": 1 },
        }
    },
    "OriginScanner": {
        "display_name": "Origin Scanner",
        "output_value_type": "Scanner",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        }
    },
    
    # Prop nodes
    "BoxProp": {
        "display_name": "Box Prop",
        "output_value_type": "Prop",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "BoxBlockType": { "gd_type": TYPE_STRING, "default_value": "BoxBlockType" },
        },
        "connections": {
            "Range": { "value_type": "Point3D", "multi": false },
            "Material": { "value_type": "Material", "multi": false },
            "Pattern": { "value_type": "Pattern", "multi": false },
            "Scanner": { "value_type": "Scanner", "multi": false },
        }
    },
    "DensityProp": {
        "display_name": "Density Prop",
        "output_value_type": "Prop",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
        },
        "connections": {
            "Pattern": { "value_type": "Pattern", "multi": false },
            "Scanner": { "value_type": "Scanner", "multi": false },
            "Material": { "value_type": "MaterialProvider", "multi": false },
            "PlacementMask": { "value_type": "BlockMask", "multi": false },
            "Range": { "value_type": "Point3D", "multi": false },
        }
    },
    
    # Assignments nodes
    "ConstantAssignments": {
        "display_name": "Constant Assignments",
        "output_value_type": "Assignments",
        "connections": {
            "Prop": { "value_type": "Prop", "multi": false },
        }
    },
    
    # Positions Cell Noise Distance Function nodes
    "EuclideanPCNDistanceFunction": {
        "display_name": "Euclidean Distance Function",
        "output_value_type": "PCNDistanceFunction",
        "settings": {
            "Type": { "gd_type": TYPE_STRING, "default_value": "Euclidean" },
        }
    },
    
    # Environment/Tint Provider nodes
    "ConstantEnvironmentProvider": {
        "display_name": "Constant Environment Provider",
        "output_value_type": "EnvironmentProvider",
        "settings": {
            "Environment": { "gd_type": TYPE_STRING, "default_value": "" },
        }
    },
    "ConstantTintProvider": {
        "display_name": "Constant Tint Provider",
        "output_value_type": "TintProvider",
        "settings": {
            "Color": { "gd_type": TYPE_STRING, "default_value": "#FFFFFF" },
        }
    },
    
    # Positions Cell Noise Return Type nodes
    "DensityPCNReturnType": {
        "display_name": "Density Cell Noise Return Type",
        "output_value_type": "PCNReturnType",
        "settings": {
            "DefaultValue": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        },
        "connections": {
            "ChoiceDensity": { "value_type": "Density", "multi": false },
            "Delimiters": { "value_type": "DelimiterDensityPCNReturnType", "multi": true },
        }
    },
    "CellValuePCNReturnType": {
        "display_name": "Cell Value Cell Noise Return Type",
        "output_value_type": "PCNReturnType",
        "settings": {
            "DefaultValue": { "gd_type": TYPE_FLOAT, "default_value": 0.0 },
        },
        "connections": {
            "Density": { "value_type": "Density", "multi": false },
        }
    },
    
    # Terrain nodes
    "DAOTerrain": {
        "display_name": "DAO Terrain",
        "output_value_type": "Terrain",
        "settings": {
            "Type": { "gd_type": TYPE_STRING, "default_value": "DAOTerrain" },
        },
        "connections": {
            "Density": { "value_type": "Density", "multi": false },
        }
    },
    
    # Runtime nodes (no Type field)
    "Runtime": {
        "display_name": "Runtime",
        "output_value_type": "Runtime",
        "settings": {
            "Skip": { "gd_type": TYPE_BOOL, "default_value": false },
            "Runtime": { "gd_type": TYPE_INT, "default_value": 0 },
        },
        "connections": {
            "Positions": { "value_type": "Positions", "multi": false },
            "Assignments": { "value_type": "Assignments", "multi": false },
        }
    },
}


func get_node_type_default_name(node_type: String) -> String:
    if not node_schema.has(node_type):
        return node_type
    return node_schema[node_type]["display_name"]