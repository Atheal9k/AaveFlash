pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    FlashLoanReceiverBase
} from "./flashLoanContracts/FlashLoanReceiverBase.sol";
import "./flashLoanContracts/ILendingPool.sol";
import "./flashLoanContracts/ILendingPoolAddressesProvider.sol";
import "./UniswapContracts/IUniswapV2Router02.sol";
import "./UniswapContracts/IUniswapV2Factory.sol";

contract Flash is FlashLoanReceiverBase {
    address owner;
    IERC20 daiAddress = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ILendingPoolAddressesProvider provider =
        ILendingPoolAddressesProvider(
            0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5
        );
    IUniswapV2Router02 public uniswapRouter;
    IUniswapV2Router02 public sushiswapRouter;
    uint256 public flashLoanedAmount;

    uint256[] public amountToTrade;
    uint256 public tokensOut;
    uint256 public deadline;
    uint256 public ethBalance;
    uint256 public daiAmount;
    uint256 public ethAmount;
    uint256 public estimatedTokens;

    constructor(ILendingPoolAddressesProvider _aaveProvider)
        public
        FlashLoanReceiverBase(_aaveProvider)
    {
        uniswapRouter = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        sushiswapRouter = IUniswapV2Router02(
            0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
        );
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        //require(_amounts <= getBalanceInternal(address(this), _reserve), "Invalid balance, was the flashLoan successful?");
        //flash logic

        swapTokens();

        // Approve the LendingPool contract allowance to *pull* the owed amount
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 amountOwing = amounts[i].add(premiums[i]);
            flashLoanedAmount = amounts[i];
            IERC20(assets[i]).approve(address(lendingPool), amountOwing);
        }
        return true;
    }

    //call this to start flash loan
    //takes the addresses of the tokens you want to borrow
    //and the amounts
    function startFlashLoan(
        address[] calldata assets,
        uint256[] calldata amounts
    ) public {
        amountToTrade = amounts;
        address receiverAddress = address(this);

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        address onBehalfOf = address(this);

        bytes memory params = "";

        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
        lendingPool.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            0
        );
    }

    //this function will execute mid flashloan
    //swaps the amount of tokens you borrowed from Aave on Uniswap and Sushiswap
    function swapTokens() public {
        IERC20 dai = IERC20(daiAddress);
        deadline = block.timestamp + 300;

        uint256 estimatedETH =
            getEstimatedETHForToken(amountToTrade[0], address(daiAddress))[1];

        uniswapRouter.swapExactTokensForETH(
            amountToTrade[0],
            estimatedETH,
            getAssetPath(address(daiAddress)),
            address(this),
            deadline
        );

        ethBalance = address(this).balance;

        estimatedTokens = getEstimatedTokensForETH(
            ethBalance,
            address(daiAddress)
        )[1];

        sushiswapRouter.swapExactETHForTokens{value: ethBalance}(
            estimatedTokens,
            getETHPath(address(daiAddress)),
            address(this),
            deadline
        );
    }

    //this in an optional function to call to initialize how much you want to borrow
    function setAmountsToSwap(uint256[] memory _amounts) public {
        amountToTrade = _amounts;
    }

    function approvals() public {
        IERC20 dai = IERC20(daiAddress);
        dai.approve(address(uniswapRouter), amountToTrade[0]);
        dai.approve(address(sushiswapRouter), amountToTrade[0]);
    }

    function getEstimatedETHForToken(uint256 _tokenAmount, address ERC20Token)
        public
        view
        returns (uint256[] memory)
    {
        return
            uniswapRouter.getAmountsOut(_tokenAmount, getAssetPath(ERC20Token));
    }

    function getEstimatedTokensForETH(uint256 _tokenAmount, address ERC20Token)
        public
        view
        returns (uint256[] memory)
    {
        return
            sushiswapRouter.getAmountsOut(_tokenAmount, getETHPath(ERC20Token));
    }

    function getAssetPath(address Token)
        private
        view
        returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = Token;
        path[1] = uniswapRouter.WETH();

        return path;
    }

    function getAssetPathSushi(address Token)
        private
        view
        returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = Token;
        path[1] = sushiswapRouter.WETH();

        return path;
    }

    function getETHPath(address Token) private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = sushiswapRouter.WETH();
        path[1] = Token;

        return path;
    }

    receive() external payable {}
}
