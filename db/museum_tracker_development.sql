
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `cmn_scholar`
--
CREATE DATABASE IF NOT EXISTS `museum_tracker_development` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
USE `museum_tracker_development`;

-- --------------------------------------------------------

--
-- Table structure for table `citations`
--

DROP TABLE IF EXISTS `citations`;
CREATE TABLE `citations` (
  `id` int(11) NOT NULL,
  `md5` varchar(32) NOT NULL,
  `doi` varchar(255) DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  `license` varchar(255) DEFAULT NULL,
  `status` smallint(1) NOT NULL DEFAULT '0',
  `possible_authorship` tinyint(1) DEFAULT NULL,
  `possible_citation` tinyint(1) DEFAULT NULL,
  `year` int(4) DEFAULT NULL,
  `print_date` varchar(100) DEFAULT NULL,
  `bibtex` text,
  `formatted` text,
  `created` date NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- --------------------------------------------------------

--
-- Table structure for table `orcids`
--

DROP TABLE IF EXISTS `orcids`;
CREATE TABLE `orcids` (
  `id` int(11) NOT NULL,
  `citation_id` int(11) NOT NULL,
  `orcid` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- --------------------------------------------------------

--
-- Table structure for table `specimens`
--

DROP TABLE IF EXISTS `specimens`;
CREATE TABLE `specimens` (
  `id` int(11) NOT NULL,
  `citation_id` int(11) NOT NULL,
  `specimen_code` varchar(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `citations`
--
ALTER TABLE `citations`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `md5` (`md5`);

--
-- Indexes for table `orcids`
--
ALTER TABLE `orcids`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `specimens`
--
ALTER TABLE `specimens`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `citations`
--
ALTER TABLE `citations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `orcids`
--
ALTER TABLE `orcids`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `specimens`
--
ALTER TABLE `specimens`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
